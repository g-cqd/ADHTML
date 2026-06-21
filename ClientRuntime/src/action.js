// The client interpreter for `data-adh-action` — the Swift `Action` DSL (RFC-0019 §6.3-G, contract C3).
// The closed verb set get/post/put/patch/delete mirrors Swift `Action.methods` (a parity test keeps them
// in sync). On its trigger event the action serializes the enclosing form (+ `data-adh-include` fields),
// fetches with the `ADH-Request: 1` header (C1), and applies the `text/html` response (C2) to
// `data-adh-target` per `data-adh-swap`. Every failure is isolated: a rejected fetch never throws out of
// the delegated listener, so the rest of the page stays interactive (same guard discipline as wireIsland).

import { applyBehavior, parseInvocation } from "./behaviors";
import { morph, oobSwap } from "./morph";
import { S, T } from "./tokens";

/** The closed verb set, mirrored by Swift `Action.methods` (parity test). Unused by the interpreter
 * itself (it lowercases the attribute), so the bundler tree-shakes it out of the runtime — it exists for
 * the parity test only. @type {readonly string[]} */
export const ACTION_METHODS = ["get", "post", "put", "patch", "delete"];

/** Failure-safe ceiling on a single action response before it is applied to the DOM. A legitimate
 * fragment is small; this drops an adversarial/oversized body (a server bug or a hostile origin) rather
 * than feeding it to `<template>` parsing + morph — bounding the parse and the `oldById` map. */
const MAX_RESPONSE_CHARS = 2 * 1024 * 1024;

/** The event type that fires an action: explicit `data-adh-trigger`, else submit for a `<form>`, else click.
 * @param {Element} node @returns {string} */
export function actionTrigger(node) {
  return node.getAttribute(T.trigger) || (node.tagName === "FORM" ? "submit" : "click");
}

/** Run an action element: debounce, then perform it. The timer is keyed per element so a fast typist
 * coalesces to a single request. Never throws (perform is guarded).
 * @param {Element} node @param {import("./wire").WireState} state @param {Document} doc @returns {void} */
export function runAction(node, state, doc) {
  const ms = Number(node.getAttribute(T.debounce)) || 0;
  const go = () => void perform(node, state, doc);
  if (ms <= 0) return go();
  const timed = /** @type {{ _adhT?: ReturnType<typeof setTimeout> }} */ (/** @type {unknown} */ (node));
  clearTimeout(timed._adhT);
  timed._adhT = setTimeout(go, ms);
}

/** Serialize request parameters: the enclosing form (or the element's own name/value), plus any
 * `data-adh-include` named fields resolved from the document (skipping ones the form already covers).
 * @param {Element} node @param {Document} doc @returns {URLSearchParams} */
function collectParams(node, doc) {
  const params = new URLSearchParams();
  const input = /** @type {HTMLInputElement} */ (node);
  const form = input.form ?? node.closest("form");
  if (form) {
    for (const [key, value] of new FormData(/** @type {HTMLFormElement} */ (form))) {
      params.append(key, String(value));
    }
  } else if (input.name) {
    params.append(input.name, input.value ?? "");
  }
  const include = node.getAttribute(T.include);
  if (include) {
    for (const name of include.split(",")) {
      const field = /** @type {HTMLInputElement | null} */ (doc.querySelector(`[name="${CSS.escape(name)}"]`));
      if (field && !(form && form.contains(field))) params.append(name, field.value ?? "");
    }
  }
  return params;
}

/** Apply the response HTML to the target per `swap`. `morph` (default) reuses the id-aware reconciler;
 * `outOfBand` lets the response name its own regions (morph.js `oobSwap`). After the DOM changes, `rewire`
 * (when provided) resumes any island/binding the response brought in — so a morphed-in editable field is
 * live, not inert (RFC-0019). `rewire` is idempotent, so re-scanning the whole target is safe.
 * @param {string} swap @param {string} html @param {Element | null} target @param {Document} doc
 * @param {((region: Element) => void) | undefined} [rewire] @returns {void} */
function applySwap(swap, html, target, doc, rewire) {
  if (swap === S.outOfBand) return oobSwap(html, doc, rewire);
  if (!target) return;
  if (swap === S.innerHTML) target.innerHTML = html;
  else if (swap === S.append) target.insertAdjacentHTML("beforeend", html);
  else morph(target, html);
  rewire?.(target);
}

/** The fetch + swap CORE, shared by the declarative action interpreter (`perform`) and the programmatic
 * component-mount bridge (`ctx.action`, mount.js) — so a widget can ONLY reach the network through the
 * signed RFC-0019 endpoint, with the `ADH-Request: 1` header (C1). Never throws (guarded by the callers).
 * @param {{method?: string, url: string, params?: URLSearchParams, swap?: string, target?: Element | null,
 *   rewire?: (region: Element) => void}} req
 * @param {Document} doc @returns {Promise<void>} */
export async function request(req, doc) {
  const method = (req.method || "get").toUpperCase();
  const params = req.params ?? new URLSearchParams();
  const headers = { "ADH-Request": "1" };
  let response;
  try {
    if (method === "GET" || method === "DELETE") {
      const query = params.toString();
      const full = query ? req.url + (req.url.includes("?") ? "&" : "?") + query : req.url;
      response = await fetch(full, { method, headers, redirect: "follow" });
    } else {
      response = await fetch(req.url, { method, headers, body: params, redirect: "follow" });
    }
  } catch {
    return; // network error -> keep the optimistic state; a later action / SSE frame reconciles
  }
  if (!response.ok) return;
  const html = await response.text();
  if (html.length > MAX_RESPONSE_CHARS) return;  // failure-safe: drop an oversized fragment, keep the page live
  applySwap(req.swap || S.morph, html, req.target ?? null, doc, req.rewire);
}

/** Perform one declarative action: optimistic pre-apply, then the shared `request` core (fetch + swap).
 * @param {Element} node @param {import("./wire").WireState} state @param {Document} doc
 * @returns {Promise<void>} */
function perform(node, state, doc) {
  // Optimistic: apply a client behavior to its cell immediately, before the network round-trip.
  const optimistic = node.getAttribute(T.optimistic);
  if (optimistic) {
    const invocation = parseInvocation(optimistic);
    if (invocation) applyBehavior(invocation, state.cells, node);
  }
  const targetId = node.getAttribute(T.target) || node.closest(`[${T.id}]`)?.getAttribute(T.id) || "";
  return request(
    {
      method: node.getAttribute(T.action) || "get",
      url: node.getAttribute(T.url) || "",
      swap: node.getAttribute(T.swap) || S.morph,
      params: collectParams(node, doc),
      target: targetId ? doc.getElementById(targetId) : null,
      rewire: state.rewire,  // resume morphed-in islands/bindings after the swap (RFC-0019)
    },
    doc);
}
