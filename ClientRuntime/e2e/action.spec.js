import { expect, test } from "@playwright/test";

// Real-browser e2e for the RFC-0019 Action layer — the reactive-hypermedia paths happy-dom can't cover:
// a real `fetch` of a server fragment morphed into a target, and a real `EventSource` pushing an SSE
// `morph` into a declaratively-connected island. The happy-dom unit tests (test/action.test.js) cover the
// interpreter logic with a stubbed fetch; these prove it end-to-end against a live server.

test("live-search action fetches a fragment over the network and morphs the target (example A)", async ({
  page,
}) => {
  await page.goto("/actions");
  await expect(page.locator("#rows")).toContainText("initial");

  // Typing fires the debounced GET /rows?q=… → the runtime morphs #rows to the returned fragment.
  await page.locator("#q").fill("abc");
  await expect(page.locator("#rows")).toContainText("match: abc");
  await expect(page.locator("#rows")).not.toContainText("initial");  // old row morphed away
});

test("Island(connect:) subscribes to SSE and morphs the island on a pushed frame (example E)", async ({
  page,
}) => {
  await page.goto("/actions");
  await expect(page.locator("#live-text")).toHaveText("waiting");
  // The runtime auto-connected #live to /stream on hydrate; the server pushes a `morph` frame ~50 ms in.
  await expect(page.locator("#live-text")).toHaveText("pushed");
});
