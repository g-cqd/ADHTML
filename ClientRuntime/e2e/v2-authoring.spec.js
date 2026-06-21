import { expect, test } from "@playwright/test";

// End-to-end proof, in a real browser (chromium), that the `$state` authoring surface works through the
// whole pipeline: the Swift engine emits the `/cart` fixture VERBATIM from a `@Component` written with the
// new API (`@State var qty`, `@Bound var inCart: Bool { $qty > 0 }`, `.increment`/`.set`, `.bind`,
// `When(inCartComputed)`) — pinned byte-for-byte by the Swift test `cartRow emits the exact wire the browser
// e2e drives` — and the committed runtime hydrates those exact bytes and runs them. The headline assertion
// is the `@Bound` recompute: clicking + flips the client-side computed `qty > 0`, with NO server round-trip,
// which mounts/unmounts the `When` template. The pure layers are unit-tested (happy-dom); this is the real
// DOM + real event-delegation glue they can't cover.

test("$state + @Bound hydrate, bind, and recompute derived state in-browser (no round-trip)", async ({
  page,
}) => {
  await page.goto("/cart");

  // Verbatim engine output carries no ids — select by the actual wire attributes the runtime reads.
  const count = page.locator("[data-e\\:text]"); // .bind(.text, to: $qty)
  const inc = page.locator('[data-c\\:click="a#0#1"]'); // .increment($qty)
  const dec = page.locator('[data-c\\:click="a#0#-1"]'); // .increment($qty, by: -1)
  const remove = page.locator('[data-c\\:click="c#0#0"]'); // .set($qty, to: 0), inside the When template

  // Hydrated from the no-JS fallback: qty 0, and `inCart` (= qty > 0) is false, so the `When(inCartComputed)`
  // template is unmounted — Remove is absent from the live DOM (template content is inert until mounted).
  await expect(count).toHaveText("0");
  await expect(remove).toHaveCount(0);

  // Click + → the increment behavior sets qty = 1 → the `.bind(.text)` effect writes "1" AND the `@Bound`
  // computed recomputes (1 > 0 → true) IN-BROWSER → the `When` template mounts Remove. This single click
  // exercises the whole new surface: behavior → signal → bound node + derived-cell recompute → conditional.
  await inc.click();
  await expect(count).toHaveText("1");
  await expect(remove).toHaveCount(1);
  await expect(remove).toBeVisible();

  await inc.click();
  await expect(count).toHaveText("2");

  // Click Remove → `.set($qty, to: 0)` → qty 0 → `inCart` recomputes false → the `When` unmounts Remove.
  await remove.click();
  await expect(count).toHaveText("0");
  await expect(remove).toHaveCount(0);

  // Click − → decrement to -1 → still not in cart, so Remove stays absent (the derived value tracks the sign).
  await dec.click();
  await expect(count).toHaveText("-1");
  await expect(remove).toHaveCount(0);
});
