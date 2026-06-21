import { expect, test } from "@playwright/test";

// `ctx.ws` (RFC-0008 Phase 2 client) in a REAL browser. A Track-4 widget opens a managed WebSocket via
// `ctx.ws`, which LAZY-LOADS the opt-in `/adh-ws.min.js` code-split bundle — the browser-only path the unit
// suite (happy-dom, resolving `./adh-ws.min.js` from a non-existent source sibling) cannot exercise. The
// fixture server pushes one frame on open and echoes a sent frame, so this proves the full round-trip:
// lazy-load → connect → receive (JSON-parsed) → send. The whole point is that the dynamic
// `import(new URL("./adh-ws.min.js", import.meta.url).href)` resolves + fetches + executes in a real engine.
test("ctx.ws lazy-loads adh-ws, connects, receives + sends in a real browser", async ({ page }) => {
  await page.goto("/ws");

  // The widget's ctx.ws() lazy-loads adh-ws + connects; the server pushes its open frame; then the widget
  // sends {ping:1} and the server echoes it. Wait for BOTH frames (no fixed sleeps).
  await expect.poll(() => page.evaluate(() => window.__wsMsgs?.length ?? 0)).toBeGreaterThanOrEqual(2);

  const msgs = await page.evaluate(() => window.__wsMsgs);
  const status = await page.evaluate(() => window.__wsStatus);

  // First frame: the server's push on open — proves lazy-load + connect + JSON-parsed receive.
  expect(JSON.parse(msgs[0])).toEqual({ from: "server", event: "open" });
  // The widget's sent {ping:1} round-tripped back — proves ctx.ws → send.
  expect(msgs.map((m) => JSON.parse(m))).toContainEqual({ ping: 1 });
  // Connection status surfaced "open" to the widget.
  expect(status).toContain("open");
});
