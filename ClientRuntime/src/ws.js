// The managed WebSocket behind `ctx.ws` (RFC-0008 Phase 2 client). Shipped as the OPT-IN `adh-ws` bundle,
// lazy-loaded by `mount.js` only when a widget calls `ctx.ws`, so it stays OUT of the ≤5 KiB core runtime.
//
// Failure-safe by construction: it never throws. A malformed URL yields an inert handle (and does NOT retry —
// a bad URL is permanent); an oversized inbound frame is dropped; a non-JSON frame is delivered as the raw
// string; a handler that throws can't break the socket; `send` after close is a no-op. It closes on the
// component's `AbortSignal`, so an unmounting widget tears the socket down (the WS counterpart to
// `ctx.fetch`'s abort-on-teardown).
//
// Resilience (v2): an UNEXPECTED drop reconnects with capped exponential backoff + jitter — a clean `open`
// resets the backoff, a deliberate `close()`/abort suppresses it. (Heartbeat/ping is a planned v3.) The retry
// is `setTimeout`-driven, not recursive — the call stack never grows.

/** Failure-safe ceiling on an inbound frame before it is handled (mirrors action.js/fetch.js). */
const MAX_FRAME_CHARS = 1 << 20;  // 1 MiB
/** Backoff ceiling — at most one reconnect attempt per 30 s once a connection keeps failing. */
const MAX_BACKOFF_MS = 30_000;
/** Base backoff (doubled per attempt, then jittered 50–100%). */
const BASE_BACKOFF_MS = 250;

/** Open a managed WebSocket. Returns a handle `{ send, close }` immediately (never throws); inbound frames
 * arrive via `onMessage` (JSON-parsed, or the raw string), connection state via `onStatus`. An unexpected
 * drop reconnects automatically until `close()`/abort.
 * @param {string} url
 * @param {AbortSignal} [signal] closes the socket + stops reconnects when aborted (the teardown signal)
 * @param {{onMessage?: (value: unknown) => void, onStatus?: (state: string) => void}} [opts]
 * @returns {{ send: (message: unknown) => void, close: () => void }} */
export function open(url, signal, opts = {}) {
  /** @type {WebSocket | undefined} */
  let socket;
  let attempts = 0;
  let stopped = false;

  const status = (/** @type {string} */ state) => {
    try {
      opts.onStatus?.(state);
    } catch {
      // a status handler must not break the socket
    }
  };

  const handleMessage = (/** @type {MessageEvent} */ event) => {
    const data = typeof event.data === "string" ? event.data : "";
    if (data.length > MAX_FRAME_CHARS) return;  // drop an oversized frame before parsing
    let value = /** @type {unknown} */ (data);
    try {
      value = JSON.parse(data);
    } catch {
      // not JSON — deliver the raw string
    }
    try {
      opts.onMessage?.(value);
    } catch {
      // a message handler must not break the socket
    }
  };

  const connect = () => {
    if (stopped) return;
    status("connecting");
    try {
      socket = new WebSocket(url);
    } catch {
      stopped = true;  // malformed URL — a permanent failure, never retry
      status("closed");
      return;
    }
    socket.onopen = () => {
      attempts = 0;  // a clean connection resets the backoff
      status("open");
    };
    socket.onmessage = handleMessage;
    socket.onclose = () => {
      status("closed");
      reconnect();  // an unexpected drop retries; a deliberate close()/abort has set `stopped`
    };
  };

  const reconnect = () => {
    if (stopped) return;
    attempts += 1;
    // Capped exponential backoff with 50–100% jitter (de-synchronize a herd reconnecting after a blip).
    const delay = Math.min(MAX_BACKOFF_MS, BASE_BACKOFF_MS * 2 ** (attempts - 1)) * (0.5 + Math.random() * 0.5);
    setTimeout(connect, delay);
  };

  const close = () => {
    stopped = true;  // deliberate → suppress reconnect
    try {
      socket?.close();
    } catch {
      // already closing/closed
    }
  };

  if (signal) {
    if (signal.aborted) stopped = true;
    else signal.addEventListener("abort", close, { once: true });
  }
  connect();

  return {
    send(message) {
      try {
        if (socket && socket.readyState === 1) {
          socket.send(typeof message === "string" ? message : JSON.stringify(message));
        }
      } catch {
        // socket not open / send failed — never throw out of a widget
      }
    },
    close,
  };
}
