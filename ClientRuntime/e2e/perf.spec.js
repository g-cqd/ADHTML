import { expect, test } from "@playwright/test";

// REAL-browser (chromium, native DOM) measurements — the honest numbers. happy-dom (the unit suite) is a
// JS DOM ~10-50x slower than a browser, so its millisecond figures overstate the runtime. This times two
// things the closest()/document-delegation design optimizes: bulk hydration, and per-click interaction
// latency (the full delegated round-trip at a nested target).
test("hydrate + interaction of 500 islands is fast in a real browser (native DOM)", async ({ page }) => {
  await page.goto("/perf");
  const { hydrateMs, clickMs, clicks } = await page.evaluate(() => ({
    hydrateMs: window.__hydrateMs,
    clickMs: window.__clickMs,
    clicks: window.__clickCount,
  }));

  console.log(`real-browser hydrate of 500 islands: ${hydrateMs.toFixed(3)} ms (${(hydrateMs * 1000 / 500).toFixed(1)} µs/island)`);
  console.log(`real-browser ${clicks} delegated click round-trips: ${clickMs.toFixed(3)} ms (${(clickMs * 1000 / clicks).toFixed(2)} µs/click)`);

  expect(hydrateMs).toBeLessThan(50);          // generous; native-DOM hydration is well under this
  expect(clickMs / clicks).toBeLessThan(0.5);  // < 0.5 ms per full delegated round-trip (generous)

  // Functional sanity: the burst of delegated clicks drove c0's bound node via closest() delegation
  // (the clicks landed on a nested <span>, so closest() had to walk up to the c element).
  await expect(page.locator('[b="c0"] output')).toHaveText(String(clicks));
});
