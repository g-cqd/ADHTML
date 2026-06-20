import { GlobalRegistrator } from "@happy-dom/global-registrator";
import { afterAll, beforeAll, beforeEach, expect, test } from "bun:test";

// Browser-in-the-loop tests for the action interpreter (RFC-0019 §6.3-G): the `p` branch of
// the delegated listener, fetch with the `ADH-Request` header (C1), and the swap apply (C2/C3). `fetch` is
// stubbed so we assert the exact request shape and that the response is morphed into the target — the glue
// the Swift render test can't reach. Real-network + real-layout coverage is the Playwright e2e suite.

beforeAll(() => GlobalRegistrator.register());
afterAll(() => GlobalRegistrator.unregister());

let hydrate;
let actionTrigger;
let ACTION_METHODS;
let morph;
let evalExpr;

beforeAll(async () => {
  ({ hydrate } = await import("../src/runtime"));
  ({ actionTrigger, ACTION_METHODS } = await import("../src/action"));
  ({ morph } = await import("../src/morph"));
  ({ evalExpr } = await import("../src/expr"));
});

/** The captured requests + the canned response for the current test. @type {{calls: any[]}} */
let net;
const realFetch = globalThis.fetch;
afterAll(() => {
  globalThis.fetch = realFetch;
});

/** Stub `fetch` to capture each call and return `html` (with `ok`). */
function stubFetch(html, ok = true) {
  net = { calls: [] };
  globalThis.fetch = (url, init) => {
    net.calls.push({ url: String(url), init });
    return Promise.resolve({ ok, status: ok ? 200 : 500, text: () => Promise.resolve(html) });
  };
}

/** Let the in-flight action settle (fetch + .text() are two microtask hops). */
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

/** Hydrate `html` in a FRESH document. The runtime adds document-level listeners; a page hydrates once,
 * so each test needs its own document or the listeners accumulate (one click → N fetches). */
function mount(html) {
  const doc = document.implementation.createHTMLDocument("t");
  doc.body.innerHTML = html;
  hydrate(doc);
  return doc;
}

test("a GET action fetches with the ADH-Request header + query string, then morphs the target", async () => {
  stubFetch(`<li id="r1">A</li><li id="r2">B</li>`);
  const doc = mount(`
    <div data-a data-b="isle" data-c="load">
      <input name="q" value="ab" data-p="get" data-q="/rows"
             data-r="input" data-u="rows" data-v="a">
    </div>
    <ul id="rows"><li id="r0">old</li></ul>
    <script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[],"islands":[{"id":"isle","on":"load","scope":[]}]}</script>`);

  doc.querySelector("input").dispatchEvent(new Event("input", { bubbles: true }));
  await flush();

  expect(net.calls.length).toBe(1);
  expect(net.calls[0].url).toBe("/rows?q=ab");
  expect(net.calls[0].init.method).toBe("GET");
  expect(net.calls[0].init.headers["ADH-Request"]).toBe("1");
  // Morphed: the server rows replaced the old one, by id.
  expect(doc.getElementById("rows").querySelector("#r0")).toBeNull();
  expect(doc.getElementById("rows").querySelector("#r1").textContent).toBe("A");
});

test("debounce coalesces a burst of triggers into a single request", async () => {
  stubFetch(`<li>x</li>`);
  const doc = mount(`
    <div data-a data-b="isle" data-c="load">
      <input name="q" value="z" data-p="get" data-q="/rows"
             data-r="input" data-s="20" data-u="rows">
    </div>
    <ul id="rows"></ul>
    <script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[],"islands":[{"id":"isle","on":"load","scope":[]}]}</script>`);

  const input = doc.querySelector("input");
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("input", { bubbles: true }));
  await new Promise((resolve) => setTimeout(resolve, 60));

  expect(net.calls.length).toBe(1);
});

test("optimistic applies a behavior to its cell instantly, before the response arrives", async () => {
  stubFetch(`<span>ignored</span>`);
  const doc = mount(`
    <div data-a data-b="isle" data-c="load">
      <span id="flag" data-e:text="0">false</span>
      <button data-p="delete" data-q="/x" data-w="b#0"
              data-u="t">remove</button>
    </div>
    <div id="t"></div>
    <script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[{"$":"sig","v":false}],"islands":[{"id":"isle","on":"load","scope":[0]}]}</script>`);

  doc.querySelector("button").dispatchEvent(new MouseEvent("click", { bubbles: true }));
  // Optimistic toggle is synchronous (runs before the awaited fetch) -> the bound node already flipped.
  expect(doc.getElementById("flag").textContent).toBe("true");
  await flush();
  expect(net.calls.length).toBe(1);
  expect(net.calls[0].init.method).toBe("DELETE");
});

test("a failed response is isolated — the target is untouched and nothing throws", async () => {
  stubFetch(`<li id="new">nope</li>`, false); // 500
  const doc = mount(`
    <div data-a data-b="isle" data-c="load">
      <button data-p="get" data-q="/rows" data-u="rows">go</button>
    </div>
    <ul id="rows"><li id="keep">keep</li></ul>
    <script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[],"islands":[{"id":"isle","on":"load","scope":[]}]}</script>`);

  doc.querySelector("button").dispatchEvent(new MouseEvent("click", { bubbles: true }));
  await flush();

  expect(net.calls.length).toBe(1);
  expect(doc.getElementById("rows").innerHTML).toContain('id="keep"');
  expect(doc.getElementById("rows").querySelector("#new")).toBeNull();
});

test("an out-of-band swap morphs each response region (attributes + children) by id", async () => {
  stubFetch(`<span data-x="pill" class="saved">Saved</span>`);
  const doc = mount(`
    <div data-a data-b="isle" data-c="load">
      <input name="title" value="x" data-p="post" data-q="/save"
             data-r="change" data-v="d">
    </div>
    <span id="pill" class="idle">Idle</span>
    <script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[],"islands":[{"id":"isle","on":"load","scope":[]}]}</script>`);

  doc.querySelector("input").dispatchEvent(new Event("change", { bubbles: true }));
  await flush();

  const pill = doc.getElementById("pill");
  expect(pill.textContent).toBe("Saved");
  expect(pill.className).toBe("saved");
});

test("actionTrigger defaults: a <form> triggers on submit, anything else on click; explicit wins", () => {
  const form = document.createElement("form");
  form.setAttribute("data-p", "post");
  expect(actionTrigger(form)).toBe("submit");

  const button = document.createElement("button");
  button.setAttribute("data-p", "delete");
  expect(actionTrigger(button)).toBe("click");

  button.setAttribute("data-r", "change");
  expect(actionTrigger(button)).toBe("change");
});

test("ACTION_METHODS mirrors the Swift Action.methods verb set (parity)", () => {
  // Keep this identical to `Action.methods` in Sources/ADHTMLCore/Hydration/Action.swift.
  expect(ACTION_METHODS).toEqual(["get", "post", "put", "patch", "delete"]);
});

test("an oversized action response is dropped before the DOM is touched (failure-safe size cap)", async () => {
  stubFetch("x".repeat(2 * 1024 * 1024 + 1));  // just over the 2 MiB cap
  const doc = mount(`
    <div data-a data-b="isle" data-c="load">
      <button data-p="get" data-q="/big" data-u="rows">go</button>
    </div>
    <ul id="rows"><li id="keep">keep</li></ul>
    <script type="application/adh-state+json" id="adh-state">{"v":1,"cells":[],"islands":[{"id":"isle","on":"load","scope":[]}]}</script>`);

  doc.querySelector("button").dispatchEvent(new MouseEvent("click", { bubbles: true }));
  await flush();

  expect(net.calls.length).toBe(1);  // it fetched...
  expect(doc.getElementById("rows").innerHTML).toContain('id="keep"');  // ...but did not apply the oversized body
});

test("evalExpr bails (undefined) on an oversized formula — the node-count ceiling (DoS guard)", () => {
  // A 5000-deep `+` chain exceeds MAX_EXPR_NODES (4096): the evaluator returns undefined instead of
  // grinding. A small formula still evaluates — so the ceiling only trips on the adversarial case.
  let formula = { i: 1 };
  for (let depth = 0; depth < 5000; depth++) formula = { o: "+", l: formula, r: { i: 1 } };
  expect(evalExpr(formula, [])).toBeUndefined();
  expect(evalExpr({ o: "+", l: { i: 2 }, r: { i: 3 } }, [])).toBe(5);
});

test("morph-apply is inert — a <script> in the response never executes (RFC-0019 §6.3-J)", () => {
  // The defense is server-side escaping (fragments are escape-by-default), but the apply path is also
  // inert by construction: morph parses through a <template> and moves nodes, and parser/innerHTML-created
  // scripts carry the "already started" flag, so inserting them never runs them.
  const doc = document.implementation.createHTMLDocument("t");
  doc.body.innerHTML = `<div id="t"><span>old</span></div>`;
  globalThis.__adhPwned = undefined;
  morph(doc.getElementById("t"), `<span>new</span><script>globalThis.__adhPwned = 1<\/script>`);
  expect(globalThis.__adhPwned).toBeUndefined();
  expect(doc.getElementById("t").textContent).toContain("new");
});
