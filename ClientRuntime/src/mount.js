// The programmatic component-mount bridge (Track 4). After hydrate(), dispatch over every
// `[data-component]` mount root and run its registered mount function — the sanctioned escape hatch for a
// genuinely bespoke widget. The function gets a small `ctx` whose ONLY network primitive is `ctx.action`,
// which reuses the action interpreter's `request` core, so a widget can reach the network only through the
// signed RFC-0019 endpoint (it can never re-implement the model). A mount function may RETURN a teardown
// function, run when its root is morphed away (the React-effect pattern). The dispatch is lazy: one
// `querySelectorAll` on a page with no components.
//
// `ctx` is deliberately minimal — `{ root, action }` — keeping the runtime within its 4.5 KiB budget: it
// hands a widget its root element and the one sanctioned network primitive, nothing more.

import { request } from "./action";
import { fetchJSON } from "./fetch";
import { T } from "./tokens";

/** name -> mount function. @type {Map<string, (root: Element, ctx: object) => unknown>} */
const registry = new Map();
/** root -> its teardown fn (or null when mounted with none); a key's presence marks the root mounted.
 * @type {WeakMap<Element, (() => void) | null>} */
const cleanups = new WeakMap();
/** root -> its lazily-created AbortController, aborted on teardown so an unmounting component's in-flight
 * `ctx.fetch` requests cancel (no leaked work, no state update after unmount). @type {WeakMap<Element, AbortController>} */
const abortControllers = new WeakMap();

/** The component's AbortController (created on first `ctx.fetch`); its signal is shared by every request the
 * widget issues, and `runCleanups` aborts it when the root is removed. @param {Element} root */
function controllerFor(root) {
  let controller = abortControllers.get(root);
  if (!controller) {
    controller = new AbortController();
    abortControllers.set(root, controller);
  }
  return controller;
}
/** @type {Document | undefined} */
let activeDoc;

/** Tear down a removed subtree — called from morph.js's remove path (the node itself and any mounted
 * descendants): run each widget's returned teardown so its listeners/timers/observers go away.
 * @param {Node} node @returns {void} */
export function runCleanups(node) {
  if (!(node instanceof Element)) return;
  const descendants = node.querySelectorAll(`[${T.component}]`);
  for (const root of node.matches(`[${T.component}]`) ? [node, ...descendants] : descendants) {
    const teardown = cleanups.get(root);
    if (teardown) {
      try {
        teardown();
      } catch {
        // a widget's teardown must not break the morph
      }
    }
    cleanups.delete(root);
    const controller = abortControllers.get(root);
    if (controller) {
      controller.abort();  // cancel the widget's in-flight ctx.fetch requests (no state update after unmount)
      abortControllers.delete(root);
    }
  }
}

/** Mount one root: build its ctx, run its registered fn, store any returned teardown.
 * @param {Element} root @returns {void} */
function mountRoot(root) {
  const fn = registry.get(/** @type {string} */ (root.getAttribute(T.component)));
  if (!fn || cleanups.has(root)) return;  // unregistered, or already mounted
  cleanups.set(root, null);  // mark mounted (idempotent), even with no teardown
  const doc = activeDoc ?? document;
  const ctx = {
    root,
    /** The ONLY network primitive: the signed RFC-0019 endpoint via the shared `request` core. */
    action: (
      /** @type {string} */ url,
      /** @type {{method?: string, swap?: string, params?: Record<string, string>, target?: string}} */ opts = {},
    ) =>
      request(
        {
          url,
          method: opts.method,
          swap: opts.swap,
          params: opts.params && new URLSearchParams(opts.params),
          target: opts.target ? doc.getElementById(opts.target) : root,
        },
        doc),
    /** A guarded JSON request against the app's own API (RFC-0008 `ctx.fetch`): the parsed value or `null`,
     * never throws, and aborted when this component is torn down. Cross-origin is governed by the server's
     * CORS, not a client block. @type {(url: string, opts?: object) => Promise<unknown | null>} */
    fetch: (/** @type {string} */ fetchURL, /** @type {object} */ fetchOpts = {}) =>
      fetchJSON(fetchURL, { ...fetchOpts, signal: controllerFor(root).signal }),
  };
  try {
    const teardown = fn(root, ctx);
    if (typeof teardown === "function") cleanups.set(root, /** @type {() => void} */ (teardown));
  } catch {
    // a failing widget must not break the page
  }
}

/** Register a mount function for a component name. If the page has already hydrated, matching un-mounted
 * roots mount immediately — so registration order vs hydration order does not matter (no boot queue needed).
 * @param {string} name @param {(root: Element, ctx: object) => unknown} fn @returns {void} */
export function mount(name, fn) {
  registry.set(name, fn);
  if (activeDoc) mountAll(activeDoc);
}

/** Dispatch over every `[data-component]` root after hydrate — runs each registered mount fn once.
 * @param {Document} doc @returns {void} */
export function mountAll(doc) {
  activeDoc = doc;
  for (const root of doc.querySelectorAll(`[${T.component}]`)) mountRoot(root);
}
