// The DOM hydration layer + entry point. It reads the inline state, then per each island's
// `data-adh-on` loading contract wires a single delegated listener (qwikloader-style) and the
// `data-adh-bind:*` bindings (each a signal effect that writes to a node). Click -> behavior ->
// signal -> bound node update. The pure logic (signals/behaviors/wire) is unit-tested; this DOM glue
// is browser-validated (smoke tests are the one remaining gap — see README).

import { applyBehavior, parseInvocation } from "./behaviors";
import { type Signal, effect } from "./signals";
import { type WireState, readState } from "./wire";

const BIND_TARGETS = ["text", "value", "class"] as const;
const DELEGATED_EVENTS = ["click", "input", "change"] as const;

function bindElements(root: Element, cells: Array<Signal<unknown>>): void {
  for (const target of BIND_TARGETS) {
    for (const element of root.querySelectorAll<HTMLElement>(`[data-adh-bind\\:${target}]`)) {
      const ref = element.getAttribute(`data-adh-bind:${target}`);
      const cell = ref === null ? undefined : cells[Number(ref)];
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

function delegate(root: Element, type: string, cells: Array<Signal<unknown>>): void {
  root.addEventListener(type, (event) => {
    const attribute = `data-adh-on:${type}`;
    for (const node of event.composedPath()) {
      if (node instanceof Element && node.hasAttribute(attribute)) {
        const invocation = parseInvocation(node.getAttribute(attribute) ?? "");
        if (invocation) applyBehavior(invocation, cells);
        return;
      }
    }
  });
}

function wireIsland(root: Element, cells: Array<Signal<unknown>>): void {
  bindElements(root, cells);
  for (const type of DELEGATED_EVENTS) delegate(root, type, cells);
}

/** Run `wire` per the island's `data-adh-on` loading contract (Astro-style directive). */
function schedule(on: string, wire: () => void): void {
  const idle = (globalThis as { requestIdleCallback?: (cb: () => void) => void }).requestIdleCallback;
  if (on === "idle") idle ? idle(wire) : setTimeout(wire, 1);
  else if (on === "visible") wire()  // TODO: IntersectionObserver (deferred — immediate is correct, not lazy)
  else if (on.startsWith("media:")) { if (matchMedia(on.slice(6)).matches) wire() }
  else wire()  // "load"
}

/** Resume every island declared in the inline state block. */
export function hydrate(doc: Document = document): void {
  const state = readState(doc);
  if (!state) return;
  for (const island of state.islands) {
    const root = doc.querySelector(`[data-adh-id="${CSS.escape(island.id)}"]`);
    if (root) schedule(island.on, () => wireIsland(root, state.cells));
  }
}

/**
 * Subscribe to a Server-Sent Events endpoint: a `patch` event carries `{ cells: { <index>: { v } } }`
 * applied to the matching signals. (A `morph` HTML-swap handler is a follow-up.) Requires ADServe SSE
 * support — see docs/integration/adserve-requirements.md.
 */
export function connect(url: string, state: WireState): EventSource {
  const source = new EventSource(url);
  source.addEventListener("patch", (event) => {
    const data = JSON.parse((event as MessageEvent).data) as { cells?: Record<string, { v: unknown }> };
    for (const [index, change] of Object.entries(data.cells ?? {})) {
      state.cells[Number(index)]?.set(change.v);
    }
  });
  return source;
}

if (typeof document !== "undefined") hydrate();
