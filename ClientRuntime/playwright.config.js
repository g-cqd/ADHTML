import { defineConfig, devices } from "@playwright/test";

// Real-browser e2e for the client runtime (chromium). The fixture server (e2e/server.js) serves a
// server-rendered page + the built runtime; `bun run build.js` must run first so `adh-runtime.min.js`
// is current. Kept separate from the fast happy-dom `bun test` suite.
export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.spec.js",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  use: { baseURL: "http://localhost:3000", trace: "on-first-retry" },
  webServer: {
    command: "bun run e2e/server.js",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
