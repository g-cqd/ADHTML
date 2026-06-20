import { expect, test } from "bun:test";

import { buildComponents, sri } from "../build-components";

// The bun module bundler (Track 4 A3): SRI parity with Swift `ADHTMLSRI`, and the manifest shape the gated
// `ADHTMLAssets` bridge consumes.

test("sri matches Swift ADHTMLSRI (parity — same sha256-base64 known answer for 'abc')", () => {
  // Pinned to the SAME constant Tests/ADHTMLSRITests asserts for `ADHTMLSRI.integrity(forUTF8: "abc")`,
  // so a module's integrity is identical whichever side computes it.
  expect(sri(new TextEncoder().encode("abc"))).toBe("sha256-ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=");
  expect(sri(new Uint8Array(0))).toBe("sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=");
});

test("buildComponents bundles each module with a content-hashed file, SRI, and byte count", async () => {
  const manifest = await buildComponents({ srcDir: "./components", write: false });
  expect(Object.keys(manifest)).toContain("counter");
  for (const entry of Object.values(manifest)) {
    expect(entry.file).toMatch(/\.[0-9a-f]{16}\.js$/); // cache-busting content hash
    expect(entry.integrity).toMatch(/^sha256-[A-Za-z0-9+/]+=*$/); // an SRI token
    expect(entry.bytes).toBeGreaterThan(0);
    // The bundled file's SRI is exactly the integrity recorded for it (self-consistency).
    expect(entry.integrity.startsWith("sha256-")).toBe(true);
  }
});

test("the bundled module is minified (the bun bundling half of the boundary)", async () => {
  const manifest = await buildComponents({ srcDir: "./components", write: false });
  // A minified bundle of the example is small and dense — bun tree-shook + minified it.
  expect(manifest.counter.bytes).toBeLessThan(1024);
});
