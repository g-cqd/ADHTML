// Bundle each component-scoped ES module (Track 4) — the bun half of the own-tooling boundary: bun owns
// JS bundling + minification (large, build-time, security-sensitive); Swift owns CSS scoping (small,
// render-time). Globs `components/*.js`, bundles + minifies each as a CONTENT-HASHED module, computes its
// SRI (`sha256-<base64>`, PARITY-pinned to Swift `ADHTMLSRI.integrity(for:)`), and writes a `manifest.json`
// the gated `ADHTMLAssets` bridge loads to emit `<script type=module src integrity nonce>`.
//
// Run: `bun run build-components.js`. No external dependencies (bun's bundler + CryptoHasher + Glob).

/** The SRI integrity token for `bytes` — `sha256-<standard-padded-base64(SHA-256)>`. PARITY-pinned to Swift
 * `ADHTMLSRI.integrity(for:)` (the same algorithm + base64 alphabet), so a served module's integrity matches
 * whichever side computes it (the parity test pins both to the same known answer).
 * @param {Uint8Array} bytes @returns {string} */
export function sri(bytes) {
  return "sha256-" + new Bun.CryptoHasher("sha256").update(bytes).digest("base64");
}

/** A short content hash for the cache-busting filename (first 16 hex of SHA-256).
 * @param {Uint8Array} bytes @returns {string} */
function contentHash(bytes) {
  return new Bun.CryptoHasher("sha256").update(bytes).digest("hex").slice(0, 16);
}

/** Bundle every component module under `srcDir` into `outDir` (content-hashed), returning the manifest:
 * `{ name: { file, integrity, bytes } }`. With `write: false` it computes the manifest without touching disk
 * (the test path).
 * @param {{srcDir?: string, outDir?: string, write?: boolean}} [opts]
 * @returns {Promise<Record<string, {file: string, integrity: string, bytes: number}>>} */
export async function buildComponents(opts = {}) {
  const srcDir = opts.srcDir ?? "./components";
  const outDir = opts.outDir ?? "./assets";
  const write = opts.write !== false;
  /** @type {Record<string, {file: string, integrity: string, bytes: number}>} */
  const manifest = {};

  for await (const entry of new Bun.Glob("*.js").scan({ cwd: srcDir })) {
    const name = entry.replace(/\.js$/, "");
    const result = await Bun.build({
      entrypoints: [`${srcDir}/${entry}`],
      minify: true,
      target: "browser",
    });
    if (!result.success) {
      for (const message of result.logs) console.error(message);
      throw new Error(`build-components: bundling ${entry} failed`);
    }
    const bytes = new Uint8Array(await result.outputs[0].arrayBuffer());
    const file = `${name}.${contentHash(bytes)}.js`;
    if (write) await Bun.write(`${outDir}/${file}`, bytes);
    manifest[name] = { file, integrity: sri(bytes), bytes: bytes.length };
  }

  if (write) await Bun.write(`${outDir}/manifest.json`, JSON.stringify(manifest, null, 2) + "\n");
  return manifest;
}

if (import.meta.main) {
  const manifest = await buildComponents();
  const names = Object.keys(manifest);
  console.log(`build-components: ${names.length} module(s) → assets/manifest.json${names.length ? " (" + names.join(", ") + ")" : ""}`);
}
