import { expect, test } from "@playwright/test";

// A REAL-browser (chromium, native DOM) hydrate measurement — the honest number. happy-dom (the unit
// suite) is a JS DOM ~10-50x slower than a browser, so its millisecond figures overstate the runtime.
test("hydrate of 500 islands is fast in a real browser (native DOM)", async ({ page }) => {
  await page.goto("/perf");
  const ms = await page.evaluate(() => (window as unknown as { __hydrateMs: number }).__hydrateMs);
  console.log(`real-browser hydrate of 500 islands: ${ms.toFixed(3)} ms (${(ms * 1000 / 500).toFixed(1)} µs/island)`);
  expect(ms).toBeLessThan(50);  // generous; native-DOM hydration is well under this

  // Functional sanity: a wired island still responds (document-level delegation reaches it).
  await page.locator('[data-adh-id="c0"] button').click();
  await expect(page.locator('[data-adh-id="c0"] span')).toHaveText("1");
});
