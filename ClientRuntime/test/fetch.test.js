import { afterEach, beforeAll, expect, test } from "bun:test";

// `fetchJSON` (src/fetch.js) is the component-facing JSON XHR primitive behind `ctx.fetch` (RFC-0008).
// It is failure-safe: ANY failure (rejection, non-2xx, non-JSON, oversize) resolves to `null`, never throws.
// `fetch` is stubbed so we assert the exact request shape + the null-on-failure contract.

let fetchJSON;
beforeAll(async () => {
  ({ fetchJSON } = await import("../src/fetch"));
});

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

/** Stub fetch with a fixed status/body; capture the calls. */
function stub(status, body, contentType = "application/json") {
  const calls = [];
  globalThis.fetch = (url, init) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(body, { status, headers: { "content-type": contentType } }));
  };
  return calls;
}

test("GET parses a JSON body and appends params to the query string", async () => {
  const calls = stub(200, JSON.stringify([{ id: 1 }]));
  const data = await fetchJSON("/api/parts", { params: { q: "bolt" } });
  expect(data).toEqual([{ id: 1 }]);
  expect(calls[0].url).toBe("/api/parts?q=bolt");
  expect(calls[0].init.method).toBe("GET");
  expect(calls[0].init.headers.Accept).toBe("application/json");
});

test("POST sends a JSON body with the right content-type and returns the parsed value", async () => {
  const calls = stub(201, JSON.stringify({ id: 9 }));
  const data = await fetchJSON("/api/parts", { method: "post", body: { name: "Nut" } });
  expect(data).toEqual({ id: 9 });
  expect(calls[0].init.method).toBe("POST");
  expect(calls[0].init.headers["Content-Type"]).toBe("application/json");
  expect(calls[0].init.body).toBe(JSON.stringify({ name: "Nut" }));
});

test("a non-2xx response resolves to null (never throws)", async () => {
  stub(500, "boom", "text/plain");
  expect(await fetchJSON("/api/x")).toBeNull();
});

test("a non-JSON 200 body resolves to null", async () => {
  stub(200, "<html>not json</html>", "text/html");
  expect(await fetchJSON("/api/x")).toBeNull();
});

test("a network error resolves to null (never throws)", async () => {
  globalThis.fetch = () => Promise.reject(new Error("offline"));
  expect(await fetchJSON("/api/x")).toBeNull();
});

test("forwards an AbortSignal to fetch (so an unmounting component can cancel)", async () => {
  const calls = stub(200, "{}");
  const ac = new AbortController();
  await fetchJSON("/api/x", { signal: ac.signal });
  expect(calls[0].init.signal).toBe(ac.signal);
});

test("does NOT carry the ADH-Request morph header (it is the JSON lane, not the morph lane)", async () => {
  const calls = stub(200, "{}");
  await fetchJSON("/api/x");
  expect(calls[0].init.headers["ADH-Request"]).toBeUndefined();
});
