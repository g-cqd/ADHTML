import { afterEach, beforeAll, expect, test } from "bun:test";

// `open` (src/ws.js) is the managed WebSocket behind `ctx.ws`. A controllable mock `WebSocket` drives the
// connection so we assert the exact behavior: status, JSON/raw/oversized inbound, gated send, abort-close,
// failure-safety. (The lazy-load wiring in mount.js is browser-only; the LOGIC is fully tested here.)

let open;
beforeAll(async () => {
  ({ open } = await import("../src/ws"));
});

const realWS = globalThis.WebSocket;
const realSetTimeout = globalThis.setTimeout;
afterEach(() => {
  globalThis.WebSocket = realWS;
  globalThis.setTimeout = realSetTimeout;
});

/** Capture scheduled reconnect timers instead of waiting — `scheduled[i].fn()` fires one on demand. */
let scheduled = [];
function mockTimers() {
  scheduled = [];
  // @ts-expect-error — test double for setTimeout
  globalThis.setTimeout = (fn, delay) => {
    scheduled.push({ fn, delay });
    return 0;
  };
}

/** A controllable mock WebSocket; the test simulates the server via `fireOpen`/`fireMessage`. */
class MockWS {
  static last = null;
  constructor(url) {
    this.url = url;
    this.readyState = 0;  // CONNECTING
    this.sent = [];
    this.onopen = this.onclose = this.onmessage = null;
    MockWS.last = this;
  }
  send(data) {
    this.sent.push(data);
  }
  close() {
    this.readyState = 3;
    this.onclose?.({});
  }
  fireOpen() {
    this.readyState = 1;
    this.onopen?.({});
  }
  fireMessage(data) {
    this.onmessage?.({ data });
  }
  fireClose() {
    this.readyState = 3;
    this.onclose?.({});
  }
}

function useMock() {
  globalThis.WebSocket = MockWS;
  MockWS.last = null;
}

test("open returns a handle and reports connecting → open", () => {
  useMock();
  const states = [];
  const handle = open("wss://x/ws", undefined, { onStatus: (s) => states.push(s) });
  expect(typeof handle.send).toBe("function");
  expect(MockWS.last.url).toBe("wss://x/ws");
  expect(states).toEqual(["connecting"]);
  MockWS.last.fireOpen();
  expect(states).toEqual(["connecting", "open"]);
});

test("inbound JSON is parsed; non-JSON arrives raw; an oversized frame is dropped", () => {
  useMock();
  const got = [];
  open("wss://x", undefined, { onMessage: (v) => got.push(v) });
  MockWS.last.fireMessage(JSON.stringify({ n: 1 }));
  MockWS.last.fireMessage("plain text");
  MockWS.last.fireMessage("x".repeat((1 << 20) + 1));  // > 1 MiB → dropped before parse
  expect(got).toEqual([{ n: 1 }, "plain text"]);
});

test("send writes only when open; objects are JSON-encoded", () => {
  useMock();
  const handle = open("wss://x");
  handle.send({ a: 1 });  // not open yet → no-op (never throws)
  expect(MockWS.last.sent).toEqual([]);
  MockWS.last.fireOpen();
  handle.send({ a: 1 });
  handle.send("raw");
  expect(MockWS.last.sent).toEqual([JSON.stringify({ a: 1 }), "raw"]);
});

test("an AbortSignal closes the socket (component teardown)", () => {
  useMock();
  const ac = new AbortController();
  open("wss://x", ac.signal);
  expect(MockWS.last.readyState).toBe(0);
  ac.abort();
  expect(MockWS.last.readyState).toBe(3);  // closed
});

test("a throwing message handler does not break the socket (failure-safe)", () => {
  useMock();
  expect(() => {
    open("wss://x", undefined, {
      onMessage: () => {
        throw new Error("boom");
      },
    });
    MockWS.last.fireMessage("{}");
  }).not.toThrow();
});

test("a malformed URL yields an inert handle and never throws", () => {
  globalThis.WebSocket = class {
    constructor() {
      throw new Error("bad url");
    }
  };
  const handle = open("::::");
  expect(typeof handle.send).toBe("function");
  expect(() => {
    handle.send("x");
    handle.close();
  }).not.toThrow();
});

test("reconnects after an unexpected drop, with a bounded backoff delay", () => {
  useMock();
  mockTimers();
  open("wss://x");
  const first = MockWS.last;
  first.fireClose();  // the server dropped the connection
  expect(scheduled.length).toBe(1);
  expect(scheduled[0].delay).toBeGreaterThan(0);
  expect(scheduled[0].delay).toBeLessThanOrEqual(30000);
  scheduled[0].fn();  // fire the reconnect timer
  expect(MockWS.last).not.toBe(first);  // a fresh socket was opened
});

test("a deliberate close() suppresses reconnection", () => {
  useMock();
  mockTimers();
  const handle = open("wss://x");
  handle.close();  // sets `stopped`; the socket's onclose must NOT schedule a retry
  expect(scheduled.length).toBe(0);
});

test("backoff grows across repeated failures (capped)", () => {
  useMock();
  mockTimers();
  open("wss://x");
  MockWS.last.fireClose();  // attempt 1 → delay in [125, 250]
  const d1 = scheduled[0].delay;
  scheduled[0].fn();  // reconnect (no clean open between)
  MockWS.last.fireClose();  // attempt 2 → delay in [250, 500]
  const d2 = scheduled[1].delay;
  expect(d2).toBeGreaterThan(d1 * 0.9);  // the range shifted up (jitter-safe margin)
  expect(d2).toBeLessThanOrEqual(30000);
});
