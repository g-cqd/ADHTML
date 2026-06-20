// `Link` boost — SPA-feel navigation (RFC-0021 P7). A boosted `<a data-link="region">` intercepts
// same-origin plain clicks: fetch the href as an ADH fragment (the `ADH-Request` header), morph the named
// region in place, and pushState — so navigation swaps one region without a full reload. popstate re-morphs
// the recorded region on Back/Forward. The real `<a href>` is the no-JS fallback (a normal navigation), and
// EVERY failure (offline, missing region, non-OK) falls back to a full navigation, so a boost never strands
// the user. Like the action interpreter, failures are isolated — nothing throws out of the listener.

import { morph } from "./morph";
import { T } from "./tokens";

/** Failure-safe ceiling on a boosted fragment before morphing it in (mirrors the action interpreter). */
const MAX_RESPONSE_CHARS = 2 * 1024 * 1024;

/** Fetch `href` as an ADH fragment and morph it into `#region`; on ANY failure do a full navigation so the
 * user always lands on the page. @param {string} href @param {string} region @param {Document} doc
 * @returns {void} */
function navigate(href, region, doc) {
  const win = doc.defaultView;
  fetch(href, { headers: { "ADH-Request": "1" }, redirect: "follow" })
    .then((response) => (response.ok ? response.text() : Promise.reject()))
    .then((html) => {
      const target = doc.getElementById(region);
      if (target && html.length <= MAX_RESPONSE_CHARS) morph(target, html);
      else win?.location.assign(href);
    })
    .catch(() => win?.location.assign(href));
}

/** The delegated boost click. Walk to the nearest boosted `<a data-link>`; for a same-origin PLAIN click
 * (left button, no modifier key, no `target`) preventDefault, morph the region, and pushState. Anything
 * else (new tab, external origin, modified click) is left to the browser's native handling.
 * @param {Event} event @param {Document} doc @returns {void} */
export function boostClick(event, doc) {
  const mouse = /** @type {MouseEvent} */ (event);
  if (mouse.button || mouse.metaKey || mouse.ctrlKey || mouse.shiftKey || mouse.altKey) return;
  const start = event.target;
  if (!(start instanceof Element)) return;
  const link = /** @type {HTMLAnchorElement | null} */ (start.closest(`a[${T.link}]`));
  const win = doc.defaultView;
  if (!link || link.target || !win || link.origin !== win.location.origin) return;
  const region = link.getAttribute(T.link);
  if (!region) return;
  event.preventDefault();
  navigate(link.href, region, doc);
  win.history.pushState({ adh: region }, "", link.href);
}

/** Install the popstate handler: on Back/Forward, re-morph the region recorded in the history entry.
 * @param {Document} doc @returns {void} */
export function boostPopstate(doc) {
  const win = doc.defaultView;
  win?.addEventListener("popstate", (event) => {
    const region = /** @type {{adh?: string} | null} */ (event.state)?.adh;
    if (region) navigate(win.location.href, region, doc);
  });
}
