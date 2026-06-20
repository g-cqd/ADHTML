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
  <div data-adh-island data-adh-id="counter" data-adh-on="load">
    <button id="inc" data-adh-on:click="increment#0#1">+</button>
    <span id="count" data-adh-bind:text="0">0</span>
  </div>
  <div style="height:2000px">spacer (pushes the lazy island below the fold)</div>
  <div data-adh-island data-adh-id="lazy" data-adh-on="visible">
    <button id="lazy-inc" data-adh-on:click="increment#1#1">+</button>
    <span id="lazy-count" data-adh-bind:text="1">0</span>
  </div>
  <script type="application/adh-state+json" id="adh-state">${STATE}</script>
  <script type="module" src="/adh-runtime.min.js"></script>
</body></html>`;

// A perf page: builds N islands client-side then times a single hydrate() in the REAL browser (native
// DOM), exposing the result on window.__hydrateMs. The auto-hydrate on module import is a no-op (the
// state block doesn't exist yet), so the measured call is the only one.
const PERF_PAGE = `<!doctype html><html><head><meta charset="utf-8"><title>perf</title></head><body>
<div id="container"></div>
<script type="module">
  import { hydrate } from "/adh-runtime.min.js";
  const N = 500;
  let html = "";
  for (let i = 0; i < N; i++) {
    html += '<div data-adh-island data-adh-id="c' + i + '" data-adh-on="load">' +
      '<button data-adh-on:click="increment#' + i + '#1">+</button>' +
      '<span data-adh-bind:text="' + i + '">0</span></div>';
  }
  const cells = Array.from({ length: N }, () => '{"$":"sig","v":0}').join(",");
  const islands = Array.from({ length: N }, (_, i) => '{"id":"c' + i + '","on":"load","scope":[' + i + ']}').join(",");
  html += '<script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[' + cells + '],"islands":[' + islands + ']}<\\/script>';
  document.getElementById("container").innerHTML = html;
  const t0 = performance.now();
  hydrate(document);
  const ms = performance.now() - t0;
  window.__hydrateMs = ms;
  document.title = "hydrated " + N + " islands in " + ms.toFixed(3) + "ms";
</script>
</body></html>`;

const PORT = Number(process.env.PORT ?? 3000);

Bun.serve({
  port: PORT,
  fetch(req) {
    const path = new URL(req.url).pathname;
    if (path === "/") {
      return new Response(PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/perf") {
      return new Response(PERF_PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/adh-runtime.min.js") {
      return new Response(Bun.file("adh-runtime.min.js"), { headers: { "content-type": "text/javascript" } });
    }
    return new Response("not found", { status: 404 });
  },
});

console.log(`e2e fixture server: http://localhost:${PORT}`);
