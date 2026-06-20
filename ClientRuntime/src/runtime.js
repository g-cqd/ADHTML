// The DOM hydration layer + entry point. It reads the inline state, then per each island's
// `data-adh-on` loading contract wires a single delegated listener (qwikloader-style) and the
// `data-adh-bind:*` bindings (each a signal effect that writes to a node). Click -> behavior ->
// signal -> bound node update. The pure logic (signals/behaviors/wire) is unit-tested; this DOM glue
// is browser-validated (Playwright e2e — see e2e/).

import { actionTrigger, runAction } from "./action";
import { applyBehavior, parseInvocation } from "./behaviors";
import { boostClick, boostPopstate } from "./boost";
import { morph } from "./morph";
import { effect } from "./signals";
import { T } from "./tokens";
import { readState } from "./wire";

const BIND_TARGETS = ["text", "value", "class"];
// One document-level listener per type (qwikloader-style). Mirrors Swift `DOMEvent.delegated` — keep in
// sync. Idle listeners for unused types cost ~nothing; only bubbling, no-default-action events are listed.
const DELEGATED_EVENTS = [
  "click", "dblclick", "input", "change", "keydown", "keyup", "keypress", "focusin", "focusout",
  "pointerdown", "pointerup", "mousedown", "mouseup", "mouseover", "mouseout", "contextmenu",
];
const BIND_SELECTOR = `[${T.bind}\\:text],[${T.bind}\\:value],[${T.bind}\\:class]`;

// Islands that have wired. The document-level delegated listener checks this so a lazy island
// (`visible`/`idle`/`media`) stays inert until it actually loads.
/** @type {WeakSet<Element>} */
const wired = new WeakSet();

/** @param {Element} root @param {Array<import("./signals").Signal<unknown>>} cells @returns {void} */
function bindElements(root, cells) {
  // One combined query for all bind targets (vs one querySelectorAll per target).
  for (const element of root.querySelectorAll(BIND_SELECTOR)) {
    for (const target of BIND_TARGETS) {
      const ref = element.getAttribute(`${T.bind}:${target}`);
      if (ref === null) continue;
      const cell = cells[Number(ref)];
      if (!cell) continue;
      effect(() => {
        const value = String(cell.get());
        if (target === "text") element.textContent = value;
        else if (target === "value") /** @type {HTMLInputElement} */ (element).value = value;
        else element.className = value;
      });
    }
  }
}

/** Wire the declarative directives within `root` (RFC-0021 P2/P6). Each is one signal effect over a cell:
 *  • `data-adh-class="name:cell;name2:cell2"` — MERGE class toggles (`classList.toggle`, never clobbers
 *    the static `className`); the name may itself contain `:` (Tailwind variants), so split on the LAST.
 *  • `data-adh-show="cell"` — toggle `display` (the node stays in the DOM).
 *  • `template[data-adh-if="cell"]` — mount/unmount: clone the template's content after it when truthy,
 *    remove it when falsy (the content is absent without JS — the on-demand-reveal fallback).
 * @param {Element} root @param {Array<import("./signals").Signal<unknown>>} cells @returns {void} */
function bindDirectives(root, cells) {
  for (const element of root.querySelectorAll(`[${T.classToggle}]`)) {
    for (const pair of (element.getAttribute(T.classToggle) ?? "").split(";")) {
      const at = pair.lastIndexOf(":");
      if (at < 1) continue;
      const name = pair.slice(0, at);
      const cell = cells[Number(pair.slice(at + 1))];
      if (cell) effect(() => element.classList.toggle(name, !!cell.get()));
    }
  }
  for (const element of root.querySelectorAll(`[${T.show}]`)) {
    const cell = cells[Number(element.getAttribute(T.show))];
    if (cell) effect(() => void (/** @type {HTMLElement} */ (element).style.display = cell.get() ? "" : "none"));
  }
  for (const template of root.querySelectorAll(`template[${T.if}]`)) {
    const cell = cells[Number(template.getAttribute(T.if))];
    if (!cell) continue;
    /** @type {ChildNode[]} */
    let mounted = [];
    effect(() => {
      const on = !!cell.get();
      if (on && !mounted.length) {
        const fragment = /** @type {HTMLTemplateElement} */ (template).content.cloneNode(true);
        mounted = [.../** @type {DocumentFragment} */ (fragment).childNodes];
        template.after(fragment);
      } else if (!on && mounted.length) {
        for (const node of mounted) node.remove();
        mounted = [];
      }
    });
  }
  // P1: two-way binding (`v-model`). The `input` event sets the cell; an effect writes the cell back to
  // `element.value` (a programmatic change updates the field). The `!==` guard avoids a cursor jump on echo.
  for (const element of root.querySelectorAll(`[${T.model}]`)) {
    const cell = cells[Number(element.getAttribute(T.model))];
    if (!cell) continue;
    const input = /** @type {HTMLInputElement} */ (element);
    effect(() => {
      const value = String(cell.get());
      if (input.value !== value) input.value = value;
    });
    input.addEventListener("input", () => cell.set(input.value));
  }
  // P3: client list. `<template data-adh-each="cell">ROW</template>` + initial server rows (no-JS). An
  // effect rebuilds the rows from the array cell (optionally filtered by `data-adh-filter`'s query) and
  // reconciles them via morph — the template stays the first child (matched positionally), rows match by
  // key/position, so identity + focus survive a re-filter. Each row's `[data-adh-each-text]` slots take
  // the element's (escaped) text.
  for (const template of root.querySelectorAll(`template[${T.each}]`)) {
    const cell = cells[Number(template.getAttribute(T.each))];
    const parent = template.parentElement;
    const rowEl = /** @type {HTMLTemplateElement} */ (template).content.firstElementChild;
    if (!cell || !parent || !rowEl) continue;
    const filterRef = template.getAttribute(T.filter);
    const filterCell = filterRef ? cells[Number(filterRef)] : null;
    effect(() => {
      const items = /** @type {unknown[]} */ (cell.get());
      const query = filterCell ? String(filterCell.get()).toLowerCase() : null;
      let html = template.outerHTML;  // keep the template first (morph matches it positionally)
      for (const raw of items) {
        const item = String(raw);
        if (query !== null && !item.toLowerCase().includes(query)) continue;
        const row = /** @type {Element} */ (rowEl.cloneNode(true));
        for (const slot of row.querySelectorAll(`[${T.eachText}]`)) slot.textContent = item;
        html += row.outerHTML;
      }
      morph(parent, html);
    });
  }
}

/** Whether `node`'s key filter (`data-adh-keys="Enter,Escape"`) admits this event — true when there is no
 * filter (P4). A filter on a non-keyboard event never matches (its `key` is undefined).
 * @param {Element} node @param {Event} event @returns {boolean} */
function keyMatches(node, event) {
  const keys = node.getAttribute(T.keys);
  return !keys || keys.split(",").includes(/** @type {KeyboardEvent} */ (event).key);
}

/** True when `node`'s enclosing island has wired (or it has none) — the lazy-island gate shared by
 * behaviors and actions: a `visible`/`idle` island stays inert until it actually loads.
 * @param {Element} node @returns {boolean} */
function delivers(node) {
  const island = node.closest(`[${T.id}]`);
  return !island || wired.has(island);
}

/** The document-level delegated handler for one event type. From the event target, `closest()` walks up
 * to the nearest `data-adh-on:<type>` element (a behavior) and the nearest `data-adh-action` element (an
 * action) in single native calls — no `composedPath()` array allocation, no JS loop. ONE listener per
 * event type for the whole page (qwikloader-style); a click both runs a behavior and, if the action's
 * trigger is `click`, issues the action.
 * @param {string} type @param {import("./wire").WireState} state @param {Event} event @param {Document} doc
 * @returns {void} */
function delegated(type, state, event, doc) {
  const start = event.target;
  if (!(start instanceof Element)) return;
  if (type === "click") boostClick(event, doc);  // P7: intercept a boosted `<a data-link>` (SPA-feel nav)
  const onNode = start.closest(`[${T.on}\\:${type}]`);
  if (onNode && delivers(onNode) && keyMatches(onNode, event)) {  // lazy island / key filter -> inert
    const invocation = parseInvocation(onNode.getAttribute(`${T.on}:${type}`) ?? "");
    if (invocation) applyBehavior(invocation, state.cells, onNode);
    if (onNode.hasAttribute(T.prevent)) event.preventDefault();
    if (onNode.hasAttribute(T.stop)) event.stopPropagation();
  }
  if (type === "keydown") {  // P9 keymap: dispatch the entry matching event.key on one element
    const keymapNode = start.closest(`[${T.keymap}]`);
    const key = /** @type {KeyboardEvent} */ (event).key + ":";
    if (keymapNode && delivers(keymapNode)) {
      for (const entry of (keymapNode.getAttribute(T.keymap) ?? "").split(";")) {
        if (entry.startsWith(key)) {
          const invocation = parseInvocation(entry.slice(key.length));
          if (invocation) applyBehavior(invocation, state.cells, keymapNode);
          if (key !== "Backspace:") event.preventDefault();  // nav keys prevent; Backspace keeps editing
          break;
        }
      }
    }
  }
  const actionNode = start.closest(`[${T.action}]`);
  if (actionNode && delivers(actionNode) && actionTrigger(actionNode) === type) {
    runAction(actionNode, state, doc);
  }
}

/** Form `submit` is not in the delegated set (it has a native default action), so it gets its own
 * listener: an action whose trigger resolves to `submit` runs here, and we `preventDefault()` the native
 * navigation. The zero-JS fallback is exactly this prevented navigation (a normal form post).
 * @param {import("./wire").WireState} state @param {Event} event @param {Document} doc @returns {void} */
function onSubmit(state, event, doc) {
  const start = event.target;
  if (!(start instanceof Element)) return;
  const node = start.closest(`[${T.action}]`);
  if (!node || !delivers(node) || actionTrigger(node) !== "submit") return;
  event.preventDefault();
  runAction(node, state, doc);
}

/** @param {Element} root @param {Array<import("./signals").Signal<unknown>>} cells @returns {void} */
function wireIsland(root, cells) {
  bindElements(root, cells);
  bindDirectives(root, cells);  // P2 class-merge + P6 conditional (show / if)
  wired.add(root);  // the document-level listener now delivers this island's events
}

/** Wire when `root` first scrolls into view (`IntersectionObserver`); falls back to immediate if the API
 * is missing (old/headless environments) — correct, just not lazy.
 * @param {Element} root @param {() => void} wire @returns {void} */
function observeVisible(root, wire) {
  if (typeof IntersectionObserver === "undefined") {
    wire();
    return;
  }
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        observer.disconnect();
        wire();
        return;
      }
    }
  });
  observer.observe(root);
}

/** Run `wire` per the island's `data-adh-on` loading contract (Astro-style directive).
 * @param {string} on @param {Element} root @param {() => void} wire @returns {void} */
function schedule(on, root, wire) {
  const idle = globalThis.requestIdleCallback;
  if (on === "idle") idle ? idle(wire) : setTimeout(wire, 1);
  else if (on === "visible") observeVisible(root, wire);
  else if (on.startsWith("media:")) { if (matchMedia(on.slice(6)).matches) wire() }
  else wire()  // "load"
}

/** Resume every island declared in the inline state block. Each island wires independently: one
 * island's failure (a bad binding, a missing API) must not break the others, so wiring is guarded.
 * @param {Document} [doc] @returns {void} */
export function hydrate(doc = document) {
  const state = readState(doc);
  if (!state) return;
  // One delegated listener per event type for the WHOLE page (not one per island) — O(1) listeners.
  // They carry both the behavior path (`data-adh-on`) and the action path (`data-adh-action`); `submit`
  // gets a dedicated listener (it is not delegated — it has a native default action we must prevent).
  for (const type of DELEGATED_EVENTS) {
    doc.addEventListener(type, (event) => delegated(type, state, event, doc));
  }
  doc.addEventListener("submit", (event) => onSubmit(state, event, doc));
  boostPopstate(doc);  // P7: Back/Forward re-morph the recorded region (boosted-nav history)
  // One DOM query for all island roots, mapped by id (vs a full-document search per island).
  /** @type {Map<string, Element>} */
  const roots = new Map();
  for (const element of doc.querySelectorAll(`[${T.id}]`)) {
    const id = element.getAttribute(T.id);
    if (id !== null) roots.set(id, element);
  }
  for (const island of state.islands) {
    const root = roots.get(island.id);
    if (!root) continue;
    schedule(island.on, root, () => {
      try {
        wireIsland(root, state.cells);
      } catch {
        // isolate per-island failures — the rest of the page stays interactive
      }
    });
    // Declarative SSE (RFC-0019 §6.3-H, contract C5): an island carrying `data-adh-connect` subscribes to
    // a server morph/patch stream, so live cross-client updates flow in (pushed, not polled).
    const stream = root.getAttribute(T.connect);
    if (stream) connect(stream, state, doc);
  }
}

/**
 * Subscribe to a Server-Sent Events endpoint and apply live updates. Two event types:
 * - `patch`: `{ cells: { <index>: { v } } }` — sets the matching signals (fine-grained cell update).
 * - `morph`: `{ id, html }` — reconciles the island `[data-adh-id="<id>"]`'s subtree to `html`
 *   (out-of-band HTML swap, preserving focus/state by id; see morph.js).
 * Requires ADServe SSE support — see docs/integration/adserve-requirements.md.
 * @param {string} url @param {import("./wire").WireState} state @param {Document} [doc]
 * @returns {EventSource} */
export function connect(url, state, doc = document) {
  const source = new EventSource(url);
  source.addEventListener("patch", (event) => {
    const data = /** @type {{cells?: Record<string, {v: unknown}>} | null} */ (parseEventData(event));
    if (!data) return;  // malformed frame -> drop the update, never throw out of the listener
    for (const [index, change] of Object.entries(data.cells ?? {})) {
      // Bounds + integer guard: a non-index key (e.g. "__proto__"/"constructor") yields NaN and is
      // ignored, and an out-of-range index can't write past the cell array. `state.cells` is a real Array
      // (never an object literal), so this is defence-in-depth over an already-non-exploitable path.
      const i = Number(index);
      if (Number.isInteger(i) && i >= 0 && i < state.cells.length) state.cells[i]?.set(change.v);
    }
  });
  source.addEventListener("morph", (event) => {
    const data = /** @type {{id?: string, html?: string} | null} */ (parseEventData(event));
    if (data && data.id && typeof data.html === "string") {
      const target = doc.querySelector(`[${T.id}="${CSS.escape(data.id)}"]`);
      if (target) morph(target, data.html);
    }
  });
  return source;
}

/** Parse an SSE event's JSON `data`, or `null` if it is malformed (failure-safe).
 * @param {Event} event @returns {unknown} */
function parseEventData(event) {
  try {
    return JSON.parse(/** @type {MessageEvent} */ (event).data);
  } catch {
    return null;
  }
}

if (typeof document !== "undefined") hydrate();
