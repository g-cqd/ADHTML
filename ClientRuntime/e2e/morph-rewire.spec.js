import { expect, test } from "@playwright/test";

// Real-browser proof (chromium) that a server-side morph re-wires what it brings in (RFC-0019): a live-search
// input fetches a fragment and morphs an editable token-field into #panel. Before the fix the morphed-in
// field was inert; now it hydrates against the EXISTING cell and is two-way live — the field survives the
// search-morph. The pure paths are happy-dom unit-tested; this is the real fetch + real morph + real input.

test("a morphed-in editable field hydrates and is two-way live (survives a search-morph)", async ({ page }) => {
  await page.goto("/rewire");

  // The field does not exist yet — it arrives via the morph the search triggers.
  await expect(page.locator("#tok")).toHaveCount(0);

  await page.locator("#q").fill("go");  // typing fires the debounced GET → morph #panel with the fragment

  const tok = page.locator("#tok");
  const echo = page.locator("#echo");
  await expect(tok).toHaveCount(1);
  await expect(tok).toHaveValue("seed"); // model effect wired: cell → value
  await expect(echo).toHaveText("seed");

  // The morphed-in field is LIVE: editing it flows value → cell → the bound echo (two-way).
  await tok.fill("hello");
  await expect(echo).toHaveText("hello");
});
