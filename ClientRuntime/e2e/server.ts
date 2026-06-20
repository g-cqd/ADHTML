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

const PORT = Number(process.env.PORT ?? 3000);

Bun.serve({
  port: PORT,
  fetch(req) {
    const path = new URL(req.url).pathname;
    if (path === "/") {
      return new Response(PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (path === "/adh-runtime.min.js") {
      return new Response(Bun.file("adh-runtime.min.js"), { headers: { "content-type": "text/javascript" } });
    }
    return new Response("not found", { status: 404 });
  },
});

console.log(`e2e fixture server: http://localhost:${PORT}`);
