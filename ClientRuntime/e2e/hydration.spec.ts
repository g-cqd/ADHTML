import { expect, test } from "@playwright/test";

// Real-browser smoke tests (chromium) over the fixture server — the glue happy-dom can't fully cover:
// real event delegation/timing and, crucially, real-layout `IntersectionObserver` for the `visible`
// loading directive (happy-dom has no layout, so its IntersectionObserver never fires).

test("a load island wires a delegated click to its bound node", async ({ page }) => {
  await page.goto("/");
  await expect(page.locator("#count")).toHaveText("0");
  await page.locator("#inc").click();
  await expect(page.locator("#count")).toHaveText("1");
  await page.locator("#inc").click();
  await expect(page.locator("#count")).toHaveText("2");
});

test("a visible island stays inert until scrolled into view, then wires (IntersectionObserver)", async ({
  page,
}) => {
  await page.goto("/");

  // Below the fold: not wired yet. `dispatchEvent` clicks WITHOUT Playwright auto-scrolling, so the
  // island must still be inert.
  await page.locator("#lazy-inc").dispatchEvent("click");
  await expect(page.locator("#lazy-count")).toHaveText("0");

  // Scroll it into view → the real IntersectionObserver fires → the island wires.
  await page.locator("#lazy-inc").scrollIntoViewIfNeeded();
  await expect(page.locator("#lazy-count")).toHaveText("0");  // still 0; just now wired
  await page.locator("#lazy-inc").click();
  await expect(page.locator("#lazy-count")).toHaveText("1");
});
