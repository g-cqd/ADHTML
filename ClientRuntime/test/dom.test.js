import { GlobalRegistrator } from "@happy-dom/global-registrator";
import { afterAll, beforeAll, beforeEach, expect, test } from "bun:test";

// Browser-in-the-loop tests for the DOM layer (the glue the unit tests can't reach): hydration wiring,
// delegated events, reactive bindings, and the SSE morph. happy-dom provides a real DOM, so a click
// actually bubbles to the document and an effect actually writes to a node.

beforeAll(() => GlobalRegistrator.register());
afterAll(() => GlobalRegistrator.unregister());

let hydrate;
let connect;
let morph;
let readState;

beforeAll(async () => {
  ({ hydrate, connect } = await import("../src/runtime"));
  ({ morph } = await import("../src/morph"));
  ({ readState } = await import("../src/wire"));
});

beforeEach(() => {
  document.body.innerHTML = "";
});

/** A counter island + its inline state, exactly as the Swift renderer emits them. */
function mountCounter(on = "load") {
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

  const button = document.querySelector("button");
  const span = document.querySelector("span");
  expect(span.textContent).toBe("0");

  button.click();
  expect(span.textContent).toBe("1");
  button.click();
  expect(span.textContent).toBe("2");
});

test("a delegated click reaches a deeply nested target via closest()", () => {
  // The clicked node is a child of the data-adh-on element; closest() must still find the handler.
  document.body.innerHTML = `
    <div data-adh-island data-adh-id="i" data-adh-on="load">
      <button data-adh-on:click="increment#0#1"><span class="inner">+</span></button>
      <output data-adh-bind:text="0">0</output>
    </div>
    <script type="application/adh-state+json" id="adh-state">
      {"v":1,"cells":[{"$":"sig","v":0}],"islands":[{"id":"i","on":"load","scope":[0]}]}
    </script>`;
  hydrate(document);
  document.querySelector(".inner").click();  // click the inner span, not the button itself
  expect(document.querySelector("output").textContent).toBe("1");
});

/** Swap in an IntersectionObserver that fires (or not) on observe; happy-dom's never intersects. */
function stubIntersectionObserver(fire) {
  const original = globalThis.IntersectionObserver;
  class Stub {
    constructor(cb) {
      this.cb = cb;
    }
    observe(element) {
      if (fire) {
        this.cb([{ isIntersecting: true, target: element }], this);
      }
    }
    disconnect() {}
  }
  globalThis.IntersectionObserver = Stub;
  return () => {
    globalThis.IntersectionObserver = original;
  };
}

test("the visible directive wires once the island intersects", () => {
  const restore = stubIntersectionObserver(true);
  try {
    mountCounter("visible");
    hydrate(document);
    document.querySelector("button").click();
    expect(document.querySelector("span").textContent).toBe("1");
  } finally {
    restore();
  }
});

test("the visible directive stays inert until it intersects (lazy)", () => {
  const restore = stubIntersectionObserver(false);
  try {
    mountCounter("visible");
    hydrate(document);
    document.querySelector("button").click();
    expect(document.querySelector("span").textContent).toBe("0");  // never wired
  } finally {
    restore();
  }
});

test("the visible directive falls back to immediate when IntersectionObserver is unavailable", () => {
  const original = globalThis.IntersectionObserver;
  globalThis.IntersectionObserver = undefined;
  try {
    mountCounter("visible");
    hydrate(document);
    document.querySelector("button").click();
    expect(document.querySelector("span").textContent).toBe("1");
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
  const input = document.querySelector("input");
  expect(input.value).toBe("hi");
  document.querySelector("button").click();
  expect(input.value).toBe("hello");
});

test("morph reconciles a subtree and preserves a node by id", () => {
  document.body.innerHTML = `<div id="root"><p id="keep">old</p><span>gone</span></div>`;
  const root = document.getElementById("root");
  const keep = document.getElementById("keep");

  morph(root, `<p id="keep">new</p><strong>added</strong>`);

  // Same #keep node object, updated text; the <span> is gone, the <strong> added.
  expect(document.getElementById("keep")).toBe(keep);
  expect(keep.textContent).toBe("new");
  expect(root.querySelector("span")).toBeNull();
  expect(root.querySelector("strong").textContent).toBe("added");
});

test("connect applies an SSE morph event to the named island", () => {
  // Drive the morph branch of connect() directly with a synthetic EventSource (no network).
  document.body.innerHTML = `<div data-adh-id="region"><p>before</p></div>`;
  const listeners = {};
  const fakeSource = {
    addEventListener(type, fn) {
      listeners[type] = fn;
    },
  };
  globalThis.EventSource = function () {
    return fakeSource;
  };

  connect("/events", { cells: [], islands: [] }, document);
  listeners.morph({ data: JSON.stringify({ id: "region", html: "<p>after</p>" }) });

  expect(document.querySelector('[data-adh-id="region"] p').textContent).toBe("after");
});

test("a malformed inline state block degrades to null (failure-safe, page stays static)", () => {
  document.body.innerHTML = `<script type="application/adh-state+json" id="adh-state">{ broken json</script>`;
  expect(readState(document)).toBeNull();
  expect(() => hydrate(document)).not.toThrow();
});

test("connect ignores a malformed SSE frame instead of throwing", () => {
  document.body.innerHTML = `<div data-adh-id="r"><p>x</p></div>`;
  const listeners = {};
  const fakeSource = {
    addEventListener(type, fn) {
      listeners[type] = fn;
    },
  };
  globalThis.EventSource = function () {
    return fakeSource;
  };

  connect("/events", { cells: [], islands: [] }, document);
  expect(() => listeners.morph({ data: "{not json" })).not.toThrow();
  expect(() => listeners.patch({ data: "nope" })).not.toThrow();
  expect(document.querySelector("p").textContent).toBe("x");  // untouched
});

test("morph handles deep nesting iteratively and preserves a deep node by id", () => {
  let inner = `<span id="leaf">old</span>`;
  for (let i = 0; i < 60; i++) inner = `<div>${inner}</div>`;  // 60 levels (would overflow a recursive morph budget)
  document.body.innerHTML = `<div id="root">${inner}</div>`;
  const root = document.getElementById("root");
  const leaf = document.getElementById("leaf");

  let next = `<span id="leaf">new</span>`;
  for (let i = 0; i < 60; i++) next = `<div>${next}</div>`;
  morph(root, next);

  expect(document.getElementById("leaf")).toBe(leaf);  // same node, preserved through 60 levels
  expect(leaf.textContent).toBe("new");
});

test("morph reorders keyed children, preserving node identity", () => {
  document.body.innerHTML = `<ul id="list"><li id="a">A</li><li id="b">B</li><li id="c">C</li></ul>`;
  const list = document.getElementById("list");
  const a = document.getElementById("a");
  const b = document.getElementById("b");
  const c = document.getElementById("c");

  morph(list, `<li id="c">C</li><li id="a">A</li><li id="b">B</li>`);

  expect(document.getElementById("a")).toBe(a);  // same nodes, moved not recreated
  expect(document.getElementById("b")).toBe(b);
  expect(document.getElementById("c")).toBe(c);
  expect([...list.children].map((el) => el.id)).toEqual(["c", "a", "b"]);
});

test("morph inserts/removes keyed children without disturbing the rest", () => {
  document.body.innerHTML = `<ul id="list"><li id="a">A</li><li id="b">B</li></ul>`;
  const list = document.getElementById("list");
  const a = document.getElementById("a");

  morph(list, `<li id="a">A</li><li id="x">X</li><li id="b">B</li>`);  // insert x
  expect(document.getElementById("a")).toBe(a);
  expect([...list.children].map((el) => el.id)).toEqual(["a", "x", "b"]);

  morph(list, `<li id="a">A</li><li id="b">B</li>`);  // remove x
  expect(document.getElementById("a")).toBe(a);
  expect(document.getElementById("x")).toBeNull();
  expect([...list.children].map((el) => el.id)).toEqual(["a", "b"]);
});

test("an action inside a Region defaults its morph target to the Region (RFC-0020 §1.6)", async () => {
  // A Region renders as an island whose stable key is BOTH `id` and `data-adh-id`. An inner action with
  // no explicit target resolves the closest `data-adh-id` (the Region) and morphs it via getElementById —
  // the plain `id` is what makes that resolution land. No runtime change: this is the unchanged transport.
  document.body.innerHTML = `
    <div data-adh-island id="content" data-adh-id="content" data-adh-on="load">
      <button data-adh-action="get" data-adh-url="/rows">reload</button>
      <ul id="rows"><li>initial</li></ul>
    </div>
    <script type="application/adh-state+json" id="adh-state">
      {"v":1,"cells":[],"islands":[{"id":"content","on":"load","scope":[]}]}
    </script>`;
  const fragment =
    `<button data-adh-action="get" data-adh-url="/rows">reload</button><ul id="rows"><li>reloaded</li></ul>`;
  const original = globalThis.fetch;
  globalThis.fetch = /** @type {any} */ (async () => ({ ok: true, text: async () => fragment }));
  try {
    hydrate(document);
    document.querySelector("button").click();
    await new Promise((resolve) => setTimeout(resolve, 0));  // let the async action settle
    expect(document.querySelector("#content #rows").textContent).toBe("reloaded");
  } finally {
    globalThis.fetch = original;
  }
});

test("a reordered keyed input keeps its live value (state survives the move)", () => {
  document.body.innerHTML = `<form id="f"><input id="i1"><input id="i2"></form>`;
  const form = document.getElementById("f");
  document.getElementById("i1").value = "typed";  // live state, not in the HTML

  morph(form, `<input id="i2"><input id="i1">`);  // reordered

  expect(document.getElementById("i1").value).toBe("typed");
  expect([...form.children].map((el) => el.id)).toEqual(["i2", "i1"]);
});
