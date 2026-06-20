// Build + minify the runtime and gate its gzipped size (<= 6 KB, ADR-0006). Uses bun's built-in
// bundler + gzip — no external dependencies. Run: `bun run build.ts` (or `bun run build`).

const BUDGET_BYTES = 6 * 1024;

const result = await Bun.build({
  entrypoints: ["./src/runtime.ts"],
  minify: true,
  target: "browser",
});

if (!result.success) {
  for (const message of result.logs) console.error(message);
  process.exit(1);
}

const code = await result.outputs[0]!.text();
await Bun.write("./adh-runtime.min.js", code);

const gzipped = Bun.gzipSync(new TextEncoder().encode(code));
const kib = (gzipped.length / 1024).toFixed(2);
console.log(`adh-runtime.min.js: ${code.length} B raw, ${gzipped.length} B (${kib} KiB) gzipped`);

if (gzipped.length > BUDGET_BYTES) {
  console.error(`FAIL: exceeds the ${BUDGET_BYTES / 1024} KiB gzip budget`);
  process.exit(1);
}
console.log(`OK: within the ${BUDGET_BYTES / 1024} KiB gzip budget`);
