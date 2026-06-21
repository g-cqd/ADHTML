// Build + minify the runtime and gate its gzipped size (<= 5 KiB, ADR-0006). Uses bun's built-in
// bundler + gzip — no external dependencies. Run: `bun run build.js` (or `bun run build`).
//
// Wire-token MANGLING (build-time): the source reads the shared `T.<name>` constants (single source of
// truth, generated Swift-side into src/tokens.js) for readability + Swift↔JS parity. Here we inline each
// `T.<name>` to its short literal via esbuild `define`, so the `T` object tree-shakes away entirely and
// the bundle carries only the 1-char tokens — the readable source costs zero bytes in production.

const BUDGET_BYTES = 5120;  // 5 KiB (ADR-0006 amend): the full P1-P9 vocabulary + SPA-nav (P7) + store (P8) + morphed-in island re-wiring (RFC-0019). htmx ~14 KiB, Alpine ~15 KiB.

// The mangling step: inline every `T.<name>` to its short literal across the source before bundling, so
// the `T` object + its import tree-shake away and the bundle carries only the 1-char tokens. (Bun's
// `define` only handles bare identifiers, not the `T.<name>` member expression, so we do it in an onLoad.)
const maps = await import("./src/tokens.js"); // { T: attributes, B: behaviors, S: swaps }
const inlineTokens = {
  name: "adh-token-inline",
  setup(build) {
    build.onLoad({ filter: /\.js$/ }, async (args) => {
      const code = (await Bun.file(args.path).text()).replace(
        /\b([TBS])\.([A-Za-z]+)\b/g,
        (match, map, name) => (name in maps[map] ? JSON.stringify(maps[map][name]) : match),
      );
      return { contents: code, loader: "js" };
    });
  },
};

const result = await Bun.build({
  entrypoints: ["./src/runtime.js"],
  minify: true,
  target: "browser",
  plugins: [inlineTokens],
});

if (!result.success) {
  for (const message of result.logs) console.error(message);
  process.exit(1);
}

const code = await result.outputs[0].text();
await Bun.write("./adh-runtime.min.js", code);

const gzipped = Bun.gzipSync(new TextEncoder().encode(code));
const kib = (gzipped.length / 1024).toFixed(2);
console.log(`adh-runtime.min.js: ${code.length} B raw, ${gzipped.length} B (${kib} KiB) gzipped`);

if (gzipped.length > BUDGET_BYTES) {
  console.error(`FAIL: exceeds the ${BUDGET_BYTES / 1024} KiB gzip budget`);
  process.exit(1);
}
console.log(`OK: within the ${BUDGET_BYTES / 1024} KiB gzip budget`);
