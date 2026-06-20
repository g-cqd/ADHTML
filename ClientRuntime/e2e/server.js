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
    html += '<div data-adh-island data-adh-id="c' + i + '" data-adh-on="load">' +
      '<button data-adh-on:click="increment#' + i + '#1"><span class="hit">+</span></button>' +
      '<output data-adh-bind:text="' + i + '">0</output></div>';
  }
  const cells = Array.from({ length: N }, () => '{"$":"sig","v":0}').join(",");
  const islands = Array.from({ length: N }, (_, i) => '{"id":"c' + i + '","on":"load","scope":[' + i + ']}').join(",");
  html += '<script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[' + cells + '],"islands":[' + islands + ']}<\\/script>';
  document.getElementById("container").innerHTML = html;

  const t0 = performance.now();
  hydrate(document);
  window.__hydrateMs = performance.now() - t0;

  // Interaction latency: dispatch CLICKS clicks at a nested element inside c0's button.
  const hit = document.querySelector('[data-adh-id="c0"] .hit');
  const CLICKS = 2000;
  const t1 = performance.now();
  for (let i = 0; i < CLICKS; i++) hit.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  window.__clickMs = performance.now() - t1;
  window.__clickCount = CLICKS;
  document.title = "hydrated " + N + " in " + window.__hydrateMs.toFixed(2) + "ms; " + CLICKS + " clicks in " + window.__clickMs.toFixed(2) + "ms";
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
