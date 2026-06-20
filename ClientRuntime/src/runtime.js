// The DOM hydration layer + entry point. It reads the inline state, then per each island's
// `data-adh-on` loading contract wires a single delegated listener (qwikloader-style) and the
// `data-adh-bind:*` bindings (each a signal effect that writes to a node). Click -> behavior ->
// signal -> bound node update. The pure logic (signals/behaviors/wire) is unit-tested; this DOM glue
// is browser-validated (Playwright e2e — see e2e/).

import { actionTrigger, runAction } from "./action";
import { applyBehavior, parseInvocation } from "./behaviors";
import { morph } from "./morph";
import { effect } from "./signals";
import { readState } from "./wire";

const BIND_TARGETS = ["text", "value", "class"];
// One document-level listener per type (qwikloader-style). Mirrors Swift `DOMEvent.delegated` — keep in
// sync. Idle listeners for unused types cost ~nothing; only bubbling, no-default-action events are listed.
const DELEGATED_EVENTS = [
  "click", "dblclick", "input", "change", "keydown", "keyup", "keypress", "focusin", "focusout",
  "pointerdown", "pointerup", "mousedown", "mouseup", "mouseover", "mouseout", "contextmenu",
];
const BIND_SELECTOR = "[data-adh-bind\\:text],[data-adh-bind\\:value],[data-adh-bind\\:class]";

// Islands that have wired. The document-level delegated listener checks this so a lazy island
// (`visible`/`idle`/`media`) stays inert until it actually loads.
/** @type {WeakSet<Element>} */
const wired = new WeakSet();

/** @param {Element} root @param {Array<import("./signals").Signal<unknown>>} cells @returns {void} */
function bindElements(root, cells) {
  // One combined query for all bind targets (vs one querySelectorAll per target).
  for (const element of root.querySelectorAll(BIND_SELECTOR)) {
    for (const target of BIND_TARGETS) {
      const ref = element.getAttribute(`data-adh-bind:${target}`);
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

/** True when `node`'s enclosing island has wired (or it has none) — the lazy-island gate shared by
 * behaviors and actions: a `visible`/`idle` island stays inert until it actually loads.
 * @param {Element} node @returns {boolean} */
function delivers(node) {
  const island = node.closest("[data-adh-id]");
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
  const onNode = start.closest(`[data-adh-on\\:${type}]`);
  if (onNode && delivers(onNode)) {  // lazy island not wired yet -> inert
    const invocation = parseInvocation(onNode.getAttribute(`data-adh-on:${type}`) ?? "");
    if (invocation) applyBehavior(invocation, state.cells);
  }
  const actionNode = start.closest("[data-adh-action]");
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
  const node = start.closest("[data-adh-action]");
  if (!node || !delivers(node) || actionTrigger(node) !== "submit") return;
  event.preventDefault();
  runAction(node, state, doc);
}

/** @param {Element} root @param {Array<import("./signals").Signal<unknown>>} cells @returns {void} */
function wireIsland(root, cells) {
  bindElements(root, cells);
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
  // One DOM query for all island roots, mapped by id (vs a full-document search per island).
  /** @type {Map<string, Element>} */
  const roots = new Map();
  for (const element of doc.querySelectorAll("[data-adh-id]")) {
    const id = element.getAttribute("data-adh-id");
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
    const stream = root.getAttribute("data-adh-connect");
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
      state.cells[Number(index)]?.set(change.v);
    }
  });
  source.addEventListener("morph", (event) => {
    const data = /** @type {{id?: string, html?: string} | null} */ (parseEventData(event));
    if (data && data.id && typeof data.html === "string") {
      const target = doc.querySelector(`[data-adh-id="${CSS.escape(data.id)}"]`);
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
