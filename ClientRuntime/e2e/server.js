// Minimal static fixture server for the Playwright e2e suite. It serves a server-rendered page exactly
// as the Swift engine would emit it — a `load` counter island and a below-the-fold `visible` island,
// plus the inline state and the built runtime — so the browser tests exercise REAL layout
// (IntersectionObserver) and real event timing, the gaps happy-dom can't cover. No framework, just
// `Bun.serve`; the runtime is read from the committed `adh-runtime.min.js`.

const STATE = JSON.stringify({
  v: 1,
  cells: [
    { $: "sig", v: 0 },
    { $: "sig", v: 0 },
  ],
  islands: [
    { id: "counter", on: "load", scope: [0] },
    { id: "lazy", on: "visible", scope: [1] },
  ],
});

const PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>adh e2e</title></head><body>
  <div data-a data-b="counter" data-c="load">
    <button id="inc" data-c:click="a#0#1">+</button>
    <span id="count" data-e:text="0">0</span>
  </div>
  <div style="height:2000px">spacer (pushes the lazy island below the fold)</div>
  <div data-a data-b="lazy" data-c="visible">
    <button id="lazy-inc" data-c:click="a#1#1">+</button>
    <span id="lazy-count" data-e:text="1">0</span>
  </div>
  <script type="application/adh-state+json" id="adh-state">${STATE}</script>
  <script type="module" src="/adh-runtime.min.js"></script>
</body></html>`;

// A perf page: builds N islands client-side then times, in the REAL browser (native DOM): (1) a single
// hydrate(), and (2) a burst of delegated clicks dispatched at a NESTED target — so each one exercises
// the document listener's closest() up-walk -> behavior -> signal -> bound node write (the full
// interaction round-trip the closest() rewrite optimizes). Results land on window.__*. The auto-hydrate
// on module import is a no-op (no state block yet), so the measured hydrate() is the only one.
const PERF_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>perf</title></head><body>
<div id="container"></div>
<script type="module">
  import { hydrate } from "/adh-runtime.min.js";
  const N = 500;
  let html = "";
  for (let i = 0; i < N; i++) {
    html += '<div data-a data-b="c' + i + '" data-c="load">' +
      '<button data-c:click="a#' + i + '#1"><span class="hit">+</span></button>' +
      '<output data-e:text="' + i + '">0</output></div>';
  }
  const cells = Array.from({ length: N }, () => '{"$":"sig","v":0}').join(",");
  const islands = Array.from({ length: N }, (_, i) => '{"id":"c' + i + '","on":"load","scope":[' + i + ']}').join(",");
  html += '<script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[' + cells + '],"islands":[' + islands + ']}<\\/script>';
  document.getElementById("container").innerHTML = html;

  const t0 = performance.now();
  hydrate(document);
  window.__hydrateMs = performance.now() - t0;

  // Interaction latency: dispatch CLICKS clicks at a nested element inside c0's button.
  const hit = document.querySelector('[data-b="c0"] .hit');
  const CLICKS = 2000;
  const t1 = performance.now();
  for (let i = 0; i < CLICKS; i++) hit.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  window.__clickMs = performance.now() - t1;
  window.__clickCount = CLICKS;
  document.title = "hydrated " + N + " in " + window.__hydrateMs.toFixed(2) + "ms; " + CLICKS + " clicks in " + window.__clickMs.toFixed(2) + "ms";
</script>
</body></html>`;

const PORT = Number(process.env.PORT ?? 3000);

// The reactive-hypermedia (RFC-0019) Action-layer fixture: a live-search input that fetches a fragment
// and morphs #rows, and an Island(connect:) that subscribes to an SSE morph stream. Exercises the real
// network + real EventSource paths the happy-dom unit tests can't. The islands are in the inline state so
// the delegated listener treats them as wired.
const ACTIONS_STATE = JSON.stringify({
  v: 1,
  cells: [],
  islands: [
    { id: "search-isle", on: "load", scope: [] },
    { id: "live", on: "load", scope: [] },
  ],
});
const ACTIONS_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>actions</title></head><body>
  <div data-a data-b="search-isle" data-c="load">
    <input id="q" name="q" data-p="get" data-q="/rows"
           data-r="input" data-s="30" data-u="rows">
  </div>
  <ul id="rows"><li id="r-initial">initial</li></ul>
  <div data-a data-b="live" data-c="load" data-d="/stream">
    <span id="live-text">waiting</span>
  </div>
  <script type="application/adh-state+json" id="adh-state">${ACTIONS_STATE}</script>
  <script type="module" src="/adh-runtime.min.js"></script>
</body></html>`;

// The `$state` authoring fixture — VERBATIM bytes of the Swift `CartRow` (`@State var qty` + `@Bound var
// inCart: Bool { $qty > 0 }`, `.increment`/`.set`, `.bind`, `When(inCartComputed)`). Pinned byte-for-byte
// by the Swift test `cartRow emits the exact wire the browser e2e drives` (Tests/ADHTMLTests/
// V2IntegrationTests.swift). cell 0 = qty signal; cell 1 = the `@Bound` computed `qty > 0` (formula `e`
// the runtime re-evaluates client-side); `<template data-h="1">` mounts Remove when that computed is true.
// `\\u003e` keeps the serializer's inline-script-safe escape of `>` intact in the served bytes.
const CART_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>cart</title></head><body>
<div data-a data-b="c1" data-c="load"><div><button data-c:click="a#0#-1">−</button><span data-e:text="0">0</span><button data-c:click="a#0#1">+</button><template data-h="1"><button data-c:click="c#0#0">Remove</button></template></div></div><script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[{"$":"sig","v":0},{"$":"cmp","d":[0],"v":false,"e":{"o":"\\u003e","l":{"c":0},"r":{"i":0}}}],"islands":[{"id":"c1","on":"load","scope":[0,1]}]}</script>
<script type="module" src="/adh-runtime.min.js"></script>
</body></html>`;

// Morph re-wiring fixture (RFC-0019): a live-search `<input>` morphs `#panel` with an editable token-field
// (`data-i` model) + an echo (`data-e:text`), both bound to the EXISTING cell 0. Proves a morphed-in field
// hydrates — model two-way live — instead of going inert, i.e. it survives a server-side search-morph.
const TOKEN_FRAG = `<input id="tok" data-i="0" value=""><output id="echo" data-e:text="0">·</output>`;
const REWIRE_STATE = JSON.stringify({
  v: 1,
  cells: [{ $: "sig", v: "seed" }],
  islands: [{ id: "search", on: "load", scope: [0] }],
});
const REWIRE_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>rewire</title></head><body>
  <div data-a data-b="search" data-c="load">
    <input id="q" name="q" data-p="get" data-q="/token-frag" data-r="input" data-s="10" data-u="panel">
  </div>
  <div id="panel">type to load the field</div>
  <script type="application/adh-state+json" id="adh-state">${REWIRE_STATE}</script>
  <script type="module" src="/adh-runtime.min.js"></script>
</body></html>`;

/** Minimal HTML-escape for the reflected query (the fixture mirrors the server's escape-by-default). */
function escapeHtml(value) {
  return value.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
}

Bun.serve({
  port: PORT,
  fetch(req) {
    const url = new URL(req.url);
    const path = url.pathname;
    if (path === "/") {
      return new Response(PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/perf") {
      return new Response(PERF_PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/actions") {
      return new Response(ACTIONS_PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/cart") {
      return new Response(CART_PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/rewire") {
      return new Response(REWIRE_PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/token-frag") {
      return new Response(TOKEN_FRAG, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/rows") {
      // Fragment: filtered rows reflecting the query (the morph target's new children).
      const q = url.searchParams.get("q") ?? "";
      const body = `<li id="r1">match: ${escapeHtml(q)}</li><li id="r2">row two</li>`;
      return new Response(body, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/stream") {
      // SSE: push one `morph` frame for island #live shortly after the runtime connects.
      const stream = new ReadableStream({
        start(controller) {
          const data = JSON.stringify({ id: "live", html: '<span id="live-text">pushed</span>' });
          setTimeout(() => controller.enqueue(new TextEncoder().encode(`event: morph\ndata: ${data}\n\n`)), 50);
        },
      });
      return new Response(stream, {
        headers: { "content-type": "text/event-stream", "cache-control": "no-cache" },
      });
    }
    if (path === "/adh-runtime.min.js") {
      return new Response(Bun.file("adh-runtime.min.js"), { headers: { "content-type": "text/javascript" } });
    }
    return new Response("not found", { status: 404 });
  },
});

console.log(`e2e fixture server: http://localhost:${PORT}`);
