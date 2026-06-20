// Real gzipped runtime-size comparison: fetch each framework's production build(s) and gzip them with the
// same method as ADHTML's own gate. Multi-file runtimes (React core+dom, Preact core+hooks) are gzipped
// per-file and summed (how a CDN serves them). Not committed — a measurement artifact.
const targets = {
  "ADHTML (islands)": ["file:adh-runtime.min.js"],
  "Preact 10 (+hooks)": [
    "https://unpkg.com/preact@10.24.3/dist/preact.min.js",
    "https://unpkg.com/preact@10.24.3/hooks/dist/hooks.umd.js",
  ],
  "petite-vue 0.4": ["https://unpkg.com/petite-vue@0.4.1/dist/petite-vue.iife.js"],
  "Alpine 3.14": ["https://unpkg.com/alpinejs@3.14.8/dist/cdn.min.js"],
  "Vue 3.5 (runtime)": ["https://unpkg.com/vue@3.5.13/dist/vue.runtime.global.prod.js"],
  "React 18 (+dom)": [
    "https://unpkg.com/react@18.3.1/umd/react.production.min.js",
    "https://unpkg.com/react-dom@18.3.1/umd/react-dom.production.min.js",
  ],
};

for (const [name, urls] of Object.entries(targets)) {
  let min = 0, gz = 0, okAll = true;
  for (const u of urls) {
    try {
      let bytes;
      if (u.startsWith("file:")) bytes = new Uint8Array(await Bun.file(u.slice(5)).arrayBuffer());
      else {
        const r = await fetch(u);
        if (!r.ok) { okAll = false; continue; }
        bytes = new Uint8Array(await r.arrayBuffer());
      }
      min += bytes.length;
      gz += Bun.gzipSync(bytes).length;
    } catch {
      okAll = false;
    }
  }
  console.log(`${name.padEnd(22)} ${(min / 1024).toFixed(1).padStart(7)} KB min   ${(gz / 1024).toFixed(2).padStart(7)} KB gzip${okAll ? "" : "  (partial)"}`);
}
