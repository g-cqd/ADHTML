import { GlobalRegistrator } from "@happy-dom/global-registrator";
import { afterAll, beforeAll, beforeEach, expect, test } from "bun:test";

// Browser-in-the-loop tests for the DOM layer (the glue the unit tests can't reach): hydration wiring,
// delegated events, reactive bindings, and the SSE morph. happy-dom provides a real DOM, so a click
// actually bubbles through composedPath and an effect actually writes to a node.

beforeAll(() => GlobalRegistrator.register());
afterAll(() => GlobalRegistrator.unregister());

let hydrate: typeof import("../src/runtime").hydrate;
let connect: typeof import("../src/runtime").connect;
let morph: typeof import("../src/morph").morph;
let readState: typeof import("../src/wire").readState;

beforeAll(async () => {
  ({ hydrate, connect } = await import("../src/runtime"));
  ({ morph } = await import("../src/morph"));
  ({ readState } = await import("../src/wire"));
});

beforeEach(() => {
  document.body.innerHTML = "";
});

/** A counter island + its inline state, exactly as the Swift renderer emits them. */
function mountCounter(on = "load"): void {
  document.body.innerHTML = `
    <div data-adh-island data-adh-id="counter" data-adh-on="${on}">
      <button data-adh-on:click="increment#0#1">+</button>
      <span data-adh-bind:text="0">0</span>
    </div>
    <script type="application/adh-state+json" id="adh-state">
      {"v":1,"cells":[{"$":"sig","v":0}],"islands":[{"id":"counter","on":"${on}","scope":[0]}]}
    </script>`;
}

test("hydrate wires a delegated click -> behavior -> bound node update", () => {
  mountCounter();
  hydrate(document);

  const button = document.querySelector("button")!;
  const span = document.querySelector("span")!;
  expect(span.textContent).toBe("0");

  button.click();
  expect(span.textContent).toBe("1");
  button.click();
  expect(span.textContent).toBe("2");
});

/** Swap in an IntersectionObserver that fires (or not) on observe; happy-dom's never intersects. */
function stubIntersectionObserver(fire: boolean): () => void {
  const original = globalThis.IntersectionObserver;
  class Stub {
    private cb: IntersectionObserverCallback;
    constructor(cb: IntersectionObserverCallback) {
      this.cb = cb;
    }
    observe(element: Element): void {
      if (fire) {
        this.cb(
          [{ isIntersecting: true, target: element } as IntersectionObserverEntry],
          this as unknown as IntersectionObserver,
        );
      }
    }
    disconnect(): void {}
  }
  globalThis.IntersectionObserver = Stub as unknown as typeof IntersectionObserver;
  return () => {
    globalThis.IntersectionObserver = original;
  };
}

test("the visible directive wires once the island intersects", () => {
  const restore = stubIntersectionObserver(true);
  try {
    mountCounter("visible");
    hydrate(document);
    document.querySelector("button")!.click();
    expect(document.querySelector("span")!.textContent).toBe("1");
  } finally {
    restore();
  }
});

test("the visible directive stays inert until it intersects (lazy)", () => {
  const restore = stubIntersectionObserver(false);
  try {
    mountCounter("visible");
    hydrate(document);
    document.querySelector("button")!.click();
    expect(document.querySelector("span")!.textContent).toBe("0");  // never wired
  } finally {
    restore();
  }
});

test("the visible directive falls back to immediate when IntersectionObserver is unavailable", () => {
  const original = globalThis.IntersectionObserver;
  (globalThis as { IntersectionObserver?: unknown }).IntersectionObserver = undefined;
  try {
    mountCounter("visible");
    hydrate(document);
    document.querySelector("button")!.click();
    expect(document.querySelector("span")!.textContent).toBe("1");
  } finally {
    globalThis.IntersectionObserver = original;
  }
});

test("a value binding writes to an input's value", () => {
  document.body.innerHTML = `
    <div data-adh-island data-adh-id="i" data-adh-on="load">
      <input data-adh-bind:value="0">
      <button data-adh-on:click="set#0#hello">x</button>
    </div>
    <script type="application/adh-state+json" id="adh-state">
      {"v":1,"cells":[{"$":"sig","v":"hi"}],"islands":[{"id":"i","on":"load","scope":[0]}]}
    </script>`;
  hydrate(document);
  const input = document.querySelector("input")!;
  expect(input.value).toBe("hi");
  document.querySelector("button")!.click();
  expect(input.value).toBe("hello");
});

test("morph reconciles a subtree and preserves a node by id", () => {
  document.body.innerHTML = `<div id="root"><p id="keep">old</p><span>gone</span></div>`;
  const root = document.getElementById("root")!;
  const keep = document.getElementById("keep")!;

  morph(root, `<p id="keep">new</p><strong>added</strong>`);

  // Same #keep node object, updated text; the <span> is gone, the <strong> added.
  expect(document.getElementById("keep")).toBe(keep);
  expect(keep.textContent).toBe("new");
  expect(root.querySelector("span")).toBeNull();
  expect(root.querySelector("strong")!.textContent).toBe("added");
});

test("connect applies an SSE morph event to the named island", () => {
  // Drive the morph branch of connect() directly with a synthetic EventSource (no network).
  document.body.innerHTML = `<div data-adh-id="region"><p>before</p></div>`;
  const listeners: Record<string, (e: MessageEvent) => void> = {};
  const fakeSource = {
    addEventListener(type: string, fn: (e: MessageEvent) => void) {
      listeners[type] = fn;
    },
  };
  (globalThis as { EventSource?: unknown }).EventSource = function () {
    return fakeSource;
  };

  connect("/events", { cells: [], islands: [] }, document);
  listeners.morph!({ data: JSON.stringify({ id: "region", html: "<p>after</p>" }) } as MessageEvent);

  expect(document.querySelector('[data-adh-id="region"] p')!.textContent).toBe("after");
});

test("a malformed inline state block degrades to null (failure-safe, page stays static)", () => {
  document.body.innerHTML = `<script type="application/adh-state+json" id="adh-state">{ broken json</script>`;
  expect(readState(document)).toBeNull();
  expect(() => hydrate(document)).not.toThrow();
});

test("connect ignores a malformed SSE frame instead of throwing", () => {
  document.body.innerHTML = `<div data-adh-id="r"><p>x</p></div>`;
  const listeners: Record<string, (e: MessageEvent) => void> = {};
  const fakeSource = {
    addEventListener(type: string, fn: (e: MessageEvent) => void) {
      listeners[type] = fn;
    },
  };
  (globalThis as { EventSource?: unknown }).EventSource = function () {
    return fakeSource;
  };

  connect("/events", { cells: [], islands: [] }, document);
  expect(() => listeners.morph!({ data: "{not json" } as MessageEvent)).not.toThrow();
  expect(() => listeners.patch!({ data: "nope" } as MessageEvent)).not.toThrow();
  expect(document.querySelector("p")!.textContent).toBe("x");  // untouched
});

test("morph handles deep nesting iteratively and preserves a deep node by id", () => {
  let inner = `<span id="leaf">old</span>`;
  for (let i = 0; i < 60; i++) inner = `<div>${inner}</div>`;  // 60 levels (would overflow a recursive morph budget)
  document.body.innerHTML = `<div id="root">${inner}</div>`;
  const root = document.getElementById("root")!;
  const leaf = document.getElementById("leaf")!;

  let next = `<span id="leaf">new</span>`;
  for (let i = 0; i < 60; i++) next = `<div>${next}</div>`;
  morph(root, next);

  expect(document.getElementById("leaf")).toBe(leaf);  // same node, preserved through 60 levels
  expect(leaf.textContent).toBe("new");
});
