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
  for (const island of state.islands) {
    const root = doc.querySelector(`[data-adh-id="${CSS.escape(island.id)}"]`);
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
