// A guarded JSON fetch — the component-facing XHR primitive (RFC-0008 Tier-2 `ctx.fetch`). Unlike the morph
// `request` (action.js, which posts the signed `ADH-Request` endpoint and swaps HTML into the DOM), this
// issues a plain JSON request against the app's own API and returns the PARSED value. Failure-safe by
// construction: it NEVER throws — a rejected fetch (network error or abort), a non-2xx status, an oversized
// body, or a non-JSON payload all resolve to `null` — it caps the body before parsing, and it honors an
// `AbortSignal` so an unmounting component cancels its in-flight work. Cross-origin reachability is governed
// by the SERVER's CORS (ADServe `CORS` middleware) plus the browser — not a redundant client-side block that
// would defeat a legitimately CORS-allowed cross-port API.

/** Failure-safe ceiling on a response body before it is parsed (mirrors action.js's `MAX_RESPONSE_CHARS`):
 * an adversarial/oversized body is dropped rather than fed to `JSON.parse`, bounding the parse cost. */
const MAX_RESPONSE_CHARS = 2 * 1024 * 1024;

/** Issue a JSON request and return the parsed value, or `null` on ANY failure (never throws).
 * GET/DELETE carry `params` as a query string; other verbs send `body` as JSON (or `params` as form data).
 * @param {string} url
 * @param {{method?: string, params?: Record<string, string>, body?: unknown,
 *   headers?: Record<string, string>, signal?: AbortSignal}} [opts]
 * @returns {Promise<unknown | null>} */
export async function fetchJSON(url, opts = {}) {
  const verb = (opts.method || "GET").toUpperCase();
  /** @type {Record<string, string>} */
  const headers = { Accept: "application/json", ...opts.headers };
  /** @type {RequestInit} */
  const init = { method: verb, headers, redirect: "follow", signal: opts.signal };
  if (verb === "GET" || verb === "DELETE") {
    const query = opts.params ? new URLSearchParams(opts.params).toString() : "";
    if (query) url += (url.includes("?") ? "&" : "?") + query;
  } else if (opts.body !== undefined) {
    headers["Content-Type"] = "application/json";
    init.body = typeof opts.body === "string" ? opts.body : JSON.stringify(opts.body);
  } else if (opts.params) {
    init.body = new URLSearchParams(opts.params);
  }
  try {
    const response = await fetch(url, init);
    if (!response.ok) return null;
    const text = await response.text();
    if (text.length > MAX_RESPONSE_CHARS) return null;  // drop an oversized body before parsing
    return JSON.parse(text);
  } catch {
    return null;  // network error, abort, or malformed JSON — never throw out of a widget
  }
}
