import { GlobalRegistrator } from "@happy-dom/global-registrator";
import { afterAll, afterEach, beforeAll, expect, test } from "bun:test";

// The programmatic component-mount bridge (Track 4). A `[data-component]` root runs its registered mount
// function with a ctx whose only network primitive is `ctx.action` (the signed RFC-0019 endpoint via the
// shared `request` core). A returned teardown runs when the root is morphed away. `fetch` is stubbed so we
// assert the exact request shape; real-layout coverage is the Playwright e2e.

beforeAll(() => GlobalRegistrator.register());
afterAll(() => GlobalRegistrator.unregister());

let mount, mountAll, runCleanups, morph;
beforeAll(async () => {
  ({ mount, mountAll, runCleanups } = await import("../src/mount"));
  ({ morph } = await import("../src/morph"));
});

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

/** Stub fetch, capturing calls; respond with `body` (200). */
function stubFetch(body = "<p>ok</p>") {
  const calls = [];
  globalThis.fetch = (url, init) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(body, { status: 200, headers: { "content-type": "text/html" } }));
  };
  return calls;
}

test("a registered mount function runs for its [data-component] root with a ctx", () => {
  document.body.innerHTML = `<div data-0="Counter"><button>+</button></div>`;
  let seen = null;
  mount("Counter", (root, ctx) => {
    seen = { root, hasAction: typeof ctx.action === "function" };
  });
  mountAll(document);
  expect(seen).not.toBeNull();
  expect(seen.root.getAttribute("data-0")).toBe("Counter");
  expect(seen.hasAction).toBe(true);
});

test("late registration (after mountAll) mounts a matching root immediately", () => {
  document.body.innerHTML = `<div data-0="Late"></div>`;
  mountAll(document);
  let ran = false;
  mount("Late", () => {
    ran = true;
  });
  expect(ran).toBe(true);
});

test("mounting is idempotent — a second mountAll does not re-run the function", () => {
  document.body.innerHTML = `<div data-0="Once"></div>`;
  let count = 0;
  mount("Once", () => {
    count += 1;
  });
  mountAll(document);
  mountAll(document);
  expect(count).toBe(1);
});

test("ctx.action reaches the network ONLY via the signed RFC-0019 endpoint (ADH-Request header)", async () => {
  document.body.innerHTML = `<div data-0="Net"></div>`;
  const calls = stubFetch();
  let action = null;
  mount("Net", (_root, ctx) => {
    action = ctx.action;
  });
  mountAll(document);
  await action("/cart/add", { method: "post", params: { sku: "A1" } });

  expect(calls.length).toBe(1);
  expect(calls[0].init.method).toBe("POST");
  expect(calls[0].init.headers["ADH-Request"]).toBe("1");
  expect(String(calls[0].init.body)).toContain("sku=A1");
});

test("a returned teardown runs when the root is morphed away (cleanup on morph)", () => {
  document.body.innerHTML = `<section><div data-0="Live"></div></section>`;
  let torn = 0;
  mount("Live", () => () => {
    torn += 1;
  });
  mountAll(document);
  expect(torn).toBe(0);

  // Re-render the section WITHOUT the widget → morph removes the mount root → its teardown runs.
  morph(document.querySelector("section"), `<span>gone</span>`);
  expect(torn).toBe(1);
});

test("ctx.fetch issues a guarded JSON request and returns the parsed value (not the morph lane)", async () => {
  document.body.innerHTML = `<div data-0="JsonW"></div>`;
  const calls = stubFetch(JSON.stringify({ count: 3 }));
  let fetchFn = null;
  mount("JsonW", (_root, ctx) => {
    fetchFn = ctx.fetch;
  });
  mountAll(document);
  const data = await fetchFn("/api/count");
  expect(data).toEqual({ count: 3 });
  expect(calls[0].init.headers.Accept).toBe("application/json");
  expect(calls[0].init.headers["ADH-Request"]).toBeUndefined();  // JSON lane, not the signed morph endpoint
});

test("ctx.fetch is aborted when the component is torn down (no state update after unmount)", () => {
  document.body.innerHTML = `<section><div data-0="AbortW"></div></section>`;
  let signal = null;
  globalThis.fetch = (_url, init) => {
    signal = init.signal;
    return new Promise(() => {});  // never resolves — the request stays in flight
  };
  let fetchFn = null;
  mount("AbortW", (_root, ctx) => {
    fetchFn = ctx.fetch;
  });
  mountAll(document);
  void fetchFn("/api/slow");  // in flight; the signal is captured synchronously by the stub
  expect(signal.aborted).toBe(false);
  morph(document.querySelector("section"), `<span>gone</span>`);  // unmount → runCleanups aborts the controller
  expect(signal.aborted).toBe(true);
});
