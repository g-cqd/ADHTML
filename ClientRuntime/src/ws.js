// The managed WebSocket behind `ctx.ws` (RFC-0008 Phase 2 client). Shipped as the OPT-IN `adh-ws` bundle,
// lazy-loaded by `mount.js` only when a widget calls `ctx.ws`, so it stays OUT of the ≤5 KiB core runtime.
//
// Failure-safe by construction: it never throws. A bad URL yields an inert handle; an oversized inbound
// frame is dropped; a non-JSON frame is delivered as the raw string; a handler that throws can't break the
// socket; and `send` after close is a no-op. It closes on the component's `AbortSignal`, so an unmounting
// widget tears the socket down (the WS counterpart to `ctx.fetch`'s abort-on-teardown). Reconnect/backoff +
// heartbeat are a planned v2 — this v1 is the connect / receive / send / lifecycle core.

/** Failure-safe ceiling on an inbound frame before it is handled (mirrors action.js/fetch.js). */
const MAX_FRAME_CHARS = 1 << 20;  // 1 MiB

/** Open a managed WebSocket. Returns a handle `{ send, close }` immediately (never throws); inbound frames
 * arrive via `onMessage` (JSON-parsed, or the raw string), connection state via `onStatus`.
 * @param {string} url
 * @param {AbortSignal} [signal] closes the socket when aborted (the component's teardown signal)
 * @param {{onMessage?: (value: unknown) => void, onStatus?: (state: string) => void}} [opts]
 * @returns {{ send: (message: unknown) => void, close: () => void }} */
export function open(url, signal, opts = {}) {
  const status = (/** @type {string} */ state) => {
    try {
      opts.onStatus?.(state);
    } catch {
      // a status handler must not break the socket
    }
  };

  /** @type {WebSocket} */
  let socket;
  try {
    socket = new WebSocket(url);
  } catch {
    status("closed");  // malformed URL — hand back an inert, never-throwing handle
    return { send() {}, close() {} };
  }

  status("connecting");
  socket.onopen = () => status("open");
  socket.onclose = () => status("closed");
  socket.onmessage = (event) => {
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

  const close = () => {
    try {
      socket.close();
    } catch {
      // already closing/closed
    }
  };
  if (signal) {
    if (signal.aborted) close();
    else signal.addEventListener("abort", close, { once: true });
  }

  return {
    send(message) {
      try {
        if (socket.readyState === 1) {
          socket.send(typeof message === "string" ? message : JSON.stringify(message));
        }
      } catch {
        // socket not open / send failed — never throw out of a widget
      }
    },
    close,
  };
}
