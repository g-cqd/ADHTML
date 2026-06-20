// Same-machine, same-workload framework comparison (chromium, native DOM). Workload: N counters (button +
// count display), server-rendered then made interactive, then K clicks at one counter. Every framework
// runs in a FRESH page under the SAME load; min of RUNS kept. Metrics:
//   - TTI: time from hydrate/init-start until a probe click on the LAST counter actually updates the DOM
//          (true time-to-interactive — where React/Vue *async or full-tree* hydration shows its cost).
//   - µs/click: timed K-click burst at counter 0, once interactive.
// SSR HTML is each framework's idiomatic form. VDOM frameworks (React/Preact/Vue) hydrate hand-written
// SSR that matches their hyperscript render (no JSX). Directive frameworks (Alpine/petite-vue) init over
// their attribute markup. Solid uses its own renderToString markers. Frameworks that need a compiler for
// hydration (Svelte, Qwik) can't be runtime-benchmarked fairly here — covered by the size/arch table in
// the report. Best-effort: any framework that errors is skipped. Not committed — a measurement artifact.
import { chromium } from "@playwright/test";

const N = 500;
const K = 2000;
const RUNS = 3;

const server = Bun.serve({
  port: 3100,
  fetch(req) {
    const p = new URL(req.url).pathname;
    if (p === "/") return new Response("<!doctype html><html><body></body></html>", { headers: { "content-type": "text/html" } });
    if (p === "/adh-runtime.min.js") return new Response(Bun.file("adh-runtime.min.js"), { headers: { "content-type": "text/javascript" } });
    return new Response("404", { status: 404 });
  },
});

const browser = await chromium.launch();
const page = await browser.newPage();
page.on("pageerror", (e) => console.error("  page error:", e.message.split("\n")[0]));

// Injected global: poll-until-interactive (TTI) + timed K-click burst. `hydrateFn(root)` makes the SSR in
// `sel.ssr` interactive; we then probe the LAST counter until its display changes, then time K clicks on 0.
const HARNESS = `
async function runHarness(hydrateFn, sel) {
  const root = document.createElement("div");
  root.innerHTML = sel.ssr;
  document.body.appendChild(root);
  const tStart = performance.now();
  await hydrateFn(root);
  // re-query each time: hydration / first render may replace the SSR nodes (React fallback, Vue, etc.)
  const probeHit = () => root.querySelectorAll(sel.hit)[sel.N - 1];
  const probeOut = () => root.querySelectorAll(sel.out)[sel.N - 1];
  let tti = -1;
  for (let waited = 0; waited <= 4000; waited += 5) {
    probeHit().dispatchEvent(new MouseEvent("click", { bubbles: true }));
    await Promise.resolve();  // flush microtask-batched frameworks (Vue/Preact) so the probe sees the update
    if (probeOut().textContent !== "0") { tti = performance.now() - tStart; break; }
    await new Promise((r) => setTimeout(r, 5));
  }
  // Per-interaction: click + microtask-flush each, so EVERY framework performs K real DOM updates
  // (batched frameworks can't coalesce the burst into one render) — a fair "K sequential interactions".
  const hit0 = root.querySelectorAll(sel.hit)[0];
  const t1 = performance.now();
  for (let k = 0; k < sel.K; k++) { hit0.dispatchEvent(new MouseEvent("click", { bubbles: true })); await Promise.resolve(); }
  const clickMs = performance.now() - t1;
  const out0 = root.querySelectorAll(sel.out)[0];
  return { tti, clickMs, ok: out0.textContent === String(sel.K) };
}`;

const PLAIN = '<div><button><span class="hit">+</span></button><output>0</output></div>';

const vanillaFn = async ({ N, K }) => {
  let inner = "";
  for (let i = 0; i < N; i++) inner += `<div><button data-i="${i}"><span class="hit">+</span></button><output>0</output></div>`;
  const sel = { ssr: `<div>${inner}</div>`, hit: ".hit", out: "output", N, K };
  return runHarness((root) => {
    const counts = new Int32Array(N);
    const outputs = root.querySelectorAll("output");
    root.addEventListener("click", (e) => {
      const b = e.target.closest("button[data-i]");
      if (!b) return;
      const i = +b.dataset.i;
      counts[i]++;
      outputs[i].textContent = String(counts[i]);
    });
  }, sel);
};

const adhtmlFn = async ({ N, K }) => {
  const { hydrate } = await import("/adh-runtime.min.js");
  let inner = "";
  for (let i = 0; i < N; i++)
    inner += `<div data-adh-island data-adh-id="c${i}" data-adh-on="load"><button data-adh-on:click="increment#${i}#1"><span class="hit">+</span></button><output data-adh-bind:text="${i}">0</output></div>`;
  const cells = Array.from({ length: N }, () => '{"$":"sig","v":0}').join(",");
  const islands = Array.from({ length: N }, (_, i) => `{"id":"c${i}","on":"load","scope":[${i}]}`).join(",");
  const state = `<script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[${cells}],"islands":[${islands}]}<\/script>`;
  const sel = { ssr: `<div>${inner}</div>${state}`, hit: ".hit", out: "output", N, K };
  return runHarness(() => hydrate(document), sel);
};

const preactFn = async ({ N, K }) => {
  const preact = await import("https://esm.sh/preact@10.24.3");
  const { useState } = await import("https://esm.sh/preact@10.24.3/hooks");
  const h = preact.h;
  const Counter = () => {
    const [n, setN] = useState(0);
    return h("div", null, h("button", { onClick: () => setN((x) => x + 1) }, h("span", { class: "hit" }, "+")), h("output", null, String(n)));
  };
  const App = () => h("div", null, Array.from({ length: N }, (_, i) => h(Counter, { key: i })));
  let inner = "";
  for (let i = 0; i < N; i++) inner += '<div><button><span class="hit">+</span></button><output>0</output></div>';
  const sel = { ssr: `<div>${inner}</div>`, hit: ".hit", out: "output", N, K };
  return runHarness((root) => preact.hydrate(h(App), root), sel);
};

const reactFn = async ({ N, K }) => {
  const React = await import("https://esm.sh/react@18.3.1");
  const { hydrateRoot } = await import("https://esm.sh/react-dom@18.3.1/client");
  const h = React.createElement;
  const { useState } = React;
  const Counter = () => {
    const [n, setN] = useState(0);
    return h("div", null, h("button", { onClick: () => setN((x) => x + 1) }, h("span", { className: "hit" }, "+")), h("output", null, String(n)));
  };
  const App = () => h("div", null, Array.from({ length: N }, (_, i) => h(Counter, { key: i })));
  let inner = "";
  for (let i = 0; i < N; i++) inner += '<div><button><span class="hit">+</span></button><output>0</output></div>';
  const sel = { ssr: `<div>${inner}</div>`, hit: ".hit", out: "output", N, K };
  return runHarness((root) => hydrateRoot(root, h(App)), sel);
};

const vueFn = async ({ N, K }) => {
  const Vue = await import("https://esm.sh/vue@3.5.13");
  const { createSSRApp, h, ref } = Vue;
  const Counter = {
    setup() {
      const n = ref(0);
      return () => h("div", null, [h("button", { onClick: () => n.value++ }, [h("span", { class: "hit" }, "+")]), h("output", null, String(n.value))]);
    },
  };
  const App = { setup() { return () => h("div", null, Array.from({ length: N }, (_, i) => h(Counter, { key: i }))); } };
  let inner = "";
  for (let i = 0; i < N; i++) inner += '<div><button><span class="hit">+</span></button><output>0</output></div>';
  const sel = { ssr: `<div>${inner}</div>`, hit: ".hit", out: "output", N, K };
  return runHarness((root) => createSSRApp(App).mount(root), sel);
};

const alpineFn = async ({ N, K }) => {
  const Alpine = (await import("https://esm.sh/alpinejs@3.14.8")).default;
  let inner = "";
  for (let i = 0; i < N; i++) inner += '<div x-data="{n:0}"><button @click="n++"><span class="hit">+</span></button><output x-text="n">0</output></div>';
  const sel = { ssr: `<div>${inner}</div>`, hit: ".hit", out: "output", N, K };
  return runHarness(() => { window.Alpine = Alpine; Alpine.start(); }, sel);
};

const petiteVueFn = async ({ N, K }) => {
  const { createApp } = await import("https://esm.sh/petite-vue@0.4.1");
  let inner = "";
  for (let i = 0; i < N; i++) inner += '<div v-scope="{n:0}"><button @click="n++"><span class="hit">+</span></button><output>{{n}}</output></div>';
  const sel = { ssr: `<div>${inner}</div>`, hit: ".hit", out: "output", N, K };
  return runHarness((root) => createApp().mount(root), sel);
};

const solidFn = async ({ N, K }) => {
  const web = await import("https://esm.sh/solid-js@1.9.3/web");
  const { createSignal } = await import("https://esm.sh/solid-js@1.9.3");
  const html = (await import("https://esm.sh/solid-js@1.9.3/html")).default;
  const Counter = () => {
    const [n, setN] = createSignal(0);
    return html`<div><button onClick=${() => setN(n() + 1)}><span class="hit">+</span></button><output>${n}</output></div>`;
  };
  const App = () => html`<div>${() => Array.from({ length: N }, () => Counter())}</div>`;
  const ssr = web.renderToString(() => App());
  const sel = { ssr, hit: ".hit", out: "output", N, K };
  return runHarness((root) => web.hydrate(() => App(), root), sel);
};

async function measure(name, fn) {
  let bestTti = Infinity, bestC = Infinity, ok = true, ran = false;
  for (let r = 0; r < RUNS; r++) {
    await page.goto("http://localhost:3100/");
    await page.addScriptTag({ content: HARNESS });
    try {
      const res = await page.evaluate(fn, { N, K });
      if (res.tti < 0) { console.error(`  ${name}: never became interactive`); return; }
      bestTti = Math.min(bestTti, res.tti);
      bestC = Math.min(bestC, res.clickMs);
      ok = ok && res.ok;
      ran = true;
    } catch (e) {
      console.error(`  ${name}: ${String(e).split("\n")[0]}`);
      return;
    }
  }
  if (!ran) return;
  console.log(
    `${name.padEnd(22)} TTI ${bestTti.toFixed(2).padStart(8)} ms (${(bestTti * 1000 / N).toFixed(1).padStart(6)} µs/counter)   ${K} clicks ${bestC.toFixed(2).padStart(8)} ms (${(bestC * 1000 / K).toFixed(2).padStart(5)} µs/click)   ${ok ? "ok" : "MISMATCH"}`,
  );
}

console.log(`workload: ${N} counters, ${K} clicks, min of ${RUNS} runs (same machine, same load)`);
console.log(`TTI = time from hydrate/init-start until a click actually updates the DOM\n`);
await measure("Vanilla (delegated)", vanillaFn);
await measure("ADHTML (islands)", adhtmlFn);
await measure("Preact 10", preactFn);
await measure("petite-vue 0.4", petiteVueFn);
await measure("Alpine 3.14", alpineFn);
await measure("Vue 3.5", vueFn);
await measure("React 18", reactFn);
// SolidJS omitted from the live run: its SSR+hydrate path requires the compile-time dom-expressions
// transform; the runtime html`` helper does not emit hydration markers (renderToString throws). Covered
// in the size/architecture table. solidFn is kept above for reference.

await browser.close();
server.stop();
