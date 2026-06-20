// The DOM hydration layer + entry point. It reads the inline state, then per each island's
// `data-adh-on` loading contract wires a single delegated listener (qwikloader-style) and the
// `data-adh-bind:*` bindings (each a signal effect that writes to a node). Click -> behavior ->
// signal -> bound node update. The pure logic (signals/behaviors/wire) is unit-tested; this DOM glue
// is browser-validated (smoke tests are the one remaining gap — see README).

import { applyBehavior, parseInvocation } from "./behaviors";
import { morph } from "./morph";
import { type Signal, effect } from "./signals";
import { type WireState, readState } from "./wire";

const BIND_TARGETS = ["text", "value", "class"] as const;
const DELEGATED_EVENTS = ["click", "input", "change"] as const;
const BIND_SELECTOR = "[data-adh-bind\\:text],[data-adh-bind\\:value],[data-adh-bind\\:class]";

// Islands that have wired. The document-level delegated listener checks this so a lazy island
// (`visible`/`idle`/`media`) stays inert until it actually loads.
const wired = new WeakSet<Element>();

function bindElements(root: Element, cells: Array<Signal<unknown>>): void {
  // One combined query for all bind targets (vs one querySelectorAll per target).
  for (const element of root.querySelectorAll<HTMLElement>(BIND_SELECTOR)) {
    for (const target of BIND_TARGETS) {
      const ref = element.getAttribute(`data-adh-bind:${target}`);
      if (ref === null) continue;
      const cell = cells[Number(ref)];
      if (!cell) continue;
      effect(() => {
        const value = String(cell.get());
        if (target === "text") element.textContent = value;
        else if (target === "value") (element as HTMLInputElement).value = value;
        else element.className = value;
      });
    }
  }
}

/** The document-level delegated handler for one event type: find the nearest `data-adh-on:<type>`
 * element on the event path and, if its island has wired, run its behavior. ONE listener per event type
 * for the whole page (qwikloader-style) — not one per island. */
function delegated(type: string, cells: Array<Signal<unknown>>, event: Event): void {
  const attribute = `data-adh-on:${type}`;
  for (const node of event.composedPath()) {
    if (node instanceof Element && node.hasAttribute(attribute)) {
      const island = node.closest("[data-adh-id]");
      if (island && !wired.has(island)) return;  // lazy island not wired yet -> inert
      const invocation = parseInvocation(node.getAttribute(attribute) ?? "");
      if (invocation) applyBehavior(invocation, cells);
      return;
    }
  }
}

function wireIsland(root: Element, cells: Array<Signal<unknown>>): void {
  bindElements(root, cells);
  wired.add(root);  // the document-level listener now delivers this island's events
}

/** Wire when `root` first scrolls into view (`IntersectionObserver`); falls back to immediate if the API
 * is missing (old/headless environments) — correct, just not lazy. */
function observeVisible(root: Element, wire: () => void): void {
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

/** Run `wire` per the island's `data-adh-on` loading contract (Astro-style directive). */
function schedule(on: string, root: Element, wire: () => void): void {
  const idle = (globalThis as { requestIdleCallback?: (cb: () => void) => void }).requestIdleCallback;
  if (on === "idle") idle ? idle(wire) : setTimeout(wire, 1);
  else if (on === "visible") observeVisible(root, wire);
  else if (on.startsWith("media:")) { if (matchMedia(on.slice(6)).matches) wire() }
  else wire()  // "load"
}

/** Resume every island declared in the inline state block. Each island wires independently: one
 * island's failure (a bad binding, a missing API) must not break the others, so wiring is guarded. */
export function hydrate(doc: Document = document): void {
  const state = readState(doc);
  if (!state) return;
  // One delegated listener per event type for the WHOLE page (not one per island) — O(1) listeners.
  for (const type of DELEGATED_EVENTS) {
    doc.addEventListener(type, (event) => delegated(type, state.cells, event));
  }
  // One DOM query for all island roots, mapped by id (vs a full-document search per island).
  const roots = new Map<string, Element>();
  for (const element of doc.querySelectorAll("[data-adh-id]")) {
    const id = element.getAttribute("data-adh-id");
    if (id !== null) roots.set(id, element);
  }
  for (const island of state.islands) {
    const root = roots.get(island.id);
    if (root) {
      schedule(island.on, root, () => {
        try {
          wireIsland(root, state.cells);
        } catch {
          // isolate per-island failures — the rest of the page stays interactive
        }
      });
    }
  }
}

/**
 * Subscribe to a Server-Sent Events endpoint and apply live updates. Two event types:
 * - `patch`: `{ cells: { <index>: { v } } }` — sets the matching signals (fine-grained cell update).
 * - `morph`: `{ id, html }` — reconciles the island `[data-adh-id="<id>"]`'s subtree to `html`
 *   (out-of-band HTML swap, preserving focus/state by id; see morph.ts).
 * Requires ADServe SSE support — see docs/integration/adserve-requirements.md.
 */
export function connect(url: string, state: WireState, doc: Document = document): EventSource {
  const source = new EventSource(url);
  source.addEventListener("patch", (event) => {
    const data = parseEventData<{ cells?: Record<string, { v: unknown }> }>(event);
    if (!data) return;  // malformed frame -> drop the update, never throw out of the listener
    for (const [index, change] of Object.entries(data.cells ?? {})) {
      state.cells[Number(index)]?.set(change.v);
    }
  });
  source.addEventListener("morph", (event) => {
    const data = parseEventData<{ id?: string; html?: string }>(event);
    if (data && data.id && typeof data.html === "string") {
      const target = doc.querySelector(`[data-adh-id="${CSS.escape(data.id)}"]`);
      if (target) morph(target, data.html);
    }
  });
  return source;
}

/** Parse an SSE event's JSON `data`, or `null` if it is malformed (failure-safe). */
function parseEventData<T>(event: Event): T | null {
  try {
    return JSON.parse((event as MessageEvent).data) as T;
  } catch {
    return null;
  }
}

if (typeof document !== "undefined") hydrate();
