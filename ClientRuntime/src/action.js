// The client interpreter for `data-adh-action` — the Swift `Action` DSL (RFC-0019 §6.3-G, contract C3).
// The closed verb set get/post/put/patch/delete mirrors Swift `Action.methods` (a parity test keeps them
// in sync). On its trigger event the action serializes the enclosing form (+ `data-adh-include` fields),
// fetches with the `ADH-Request: 1` header (C1), and applies the `text/html` response (C2) to
// `data-adh-target` per `data-adh-swap`. Every failure is isolated: a rejected fetch never throws out of
// the delegated listener, so the rest of the page stays interactive (same guard discipline as wireIsland).

import { applyBehavior, parseInvocation } from "./behaviors";
import { morph, oobSwap } from "./morph";
import { T } from "./tokens";

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
 * `outOfBand` lets the response name its own regions (morph.js `oobSwap`).
 * @param {string} swap @param {string} html @param {Element | null} target @param {Document} doc
 * @returns {void} */
function applySwap(swap, html, target, doc) {
  if (swap === "outOfBand") return oobSwap(html, doc);
  if (!target) return;
  if (swap === "innerHTML") target.innerHTML = html;
  else if (swap === "append") target.insertAdjacentHTML("beforeend", html);
  else morph(target, html);
}

/** Perform one action: optimistic pre-apply, fetch with the `ADH-Request` header, then swap the response.
 * @param {Element} node @param {import("./wire").WireState} state @param {Document} doc
 * @returns {Promise<void>} */
async function perform(node, state, doc) {
  const method = (node.getAttribute(T.action) || "get").toUpperCase();
  const url = node.getAttribute(T.url) || "";
  const swap = node.getAttribute(T.swap) || "morph";
  const targetId =
    node.getAttribute(T.target) ||
    node.closest(`[${T.id}]`)?.getAttribute(T.id) ||
    "";

  // Optimistic: apply a client behavior to its cell immediately, before the network round-trip.
  const optimistic = node.getAttribute(T.optimistic);
  if (optimistic) {
    const invocation = parseInvocation(optimistic);
    if (invocation) applyBehavior(invocation, state.cells, node);
  }

  const params = collectParams(node, doc);
  const headers = { "ADH-Request": "1" };
  let response;
  try {
    if (method === "GET" || method === "DELETE") {
      const query = params.toString();
      const full = query ? url + (url.includes("?") ? "&" : "?") + query : url;
      response = await fetch(full, { method, headers, redirect: "follow" });
    } else {
      response = await fetch(url, { method, headers, body: params, redirect: "follow" });
    }
  } catch {
    return; // network error -> keep the optimistic state; a later action / SSE frame reconciles
  }
  if (!response.ok) return;
  const html = await response.text();
  if (html.length > MAX_RESPONSE_CHARS) return;  // failure-safe: drop an oversized fragment, keep the page live
  applySwap(swap, html, targetId ? doc.getElementById(targetId) : null, doc);
}
