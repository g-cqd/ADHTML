// A small profiling harness for the client runtime's hot paths (bun + happy-dom). Not a test — run it
// to find/track bottlenecks: `bun profile/bench.ts`. Reports min + median ms over several runs.
import { GlobalRegistrator } from "@happy-dom/global-registrator";

GlobalRegistrator.register();

const { Signal, effect } = await import("../src/signals");
const { morph } = await import("../src/morph");
const { hydrate } = await import("../src/runtime");

function bench(name: string, runs: number, fn: () => void): void {
  for (let i = 0; i < 3; i++) fn();  // warm up
  const samples: number[] = [];
  for (let r = 0; r < runs; r++) {
    const start = performance.now();
    fn();
    samples.push(performance.now() - start);
  }
  samples.sort((a, b) => a - b);
  const min = samples[0] ?? 0;
  const median = samples[runs >> 1] ?? 0;
  console.log(`${name.padEnd(30)} min ${min.toFixed(3)} ms   median ${median.toFixed(3)} ms`);
}

// 1. Signal fan-out: one signal with K subscribers, updated M times (exercises set -> propagation).
bench("signal/fanout-100sub-1000set", 50, () => {
  const signal = new Signal(0);
  for (let i = 0; i < 100; i++) effect(() => void signal.get());
  for (let i = 0; i < 1000; i++) signal.set(i);
});

// 2. Many independent signals each with one effect, updated once (typical binding churn).
bench("signal/1000-cells-1-effect", 200, () => {
  const cells = Array.from({ length: 1000 }, () => new Signal(0));
  for (const cell of cells) effect(() => void cell.get());
  for (let i = 0; i < cells.length; i++) cells[i]!.set(i);
});

// 3. morph a 1000-item keyed list to a reordered + edited version.
const oldList = Array.from({ length: 1000 }, (_, i) => `<li id="i${i}">item ${i}</li>`).join("");
const newList = Array.from({ length: 1000 }, (_, i) => `<li id="i${(i + 7) % 1000}">item ${(i + 7) % 1000} *</li>`).join("");
bench("morph/list-1000-reordered", 100, () => {
  document.body.innerHTML = `<ul id="l">${oldList}</ul>`;
  morph(document.getElementById("l")!, newList);
});

// 4. hydrate a page with 200 islands (each a counter binding).
const islandsHTML = Array.from(
  { length: 200 },
  (_, i) =>
    `<div data-adh-island data-adh-id="c${i}" data-adh-on="load">` +
    `<button data-adh-on:click="increment#${i}#1">+</button>` +
    `<span data-adh-bind:text="${i}">0</span></div>`,
).join("");
const cellsJSON = Array.from({ length: 200 }, () => `{"$":"sig","v":0}`).join(",");
const islandsJSON = Array.from({ length: 200 }, (_, i) => `{"id":"c${i}","on":"load","scope":[${i}]}`).join(",");
const pageHTML =
  islandsHTML +
  `<script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[${cellsJSON}],"islands":[${islandsJSON}]}</script>`;
bench("hydrate/200-islands", 100, () => {
  document.body.innerHTML = pageHTML;
  hydrate(document);
});
