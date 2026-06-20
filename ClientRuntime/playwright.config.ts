import { defineConfig, devices } from "@playwright/test";

// Real-browser e2e for the client runtime (chromium). The fixture server (e2e/server.ts) serves a
// server-rendered page + the built runtime; `bun run build.ts` must run first so `adh-runtime.min.js`
// is current. Kept separate from the fast happy-dom `bun test` suite.
export default defineConfig({
  testDir: "./e2e",
  testMatch: "**/*.spec.ts",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  use: { baseURL: "http://localhost:3000", trace: "on-first-retry" },
  webServer: {
    command: "bun run e2e/server.ts",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
