// Browser E2E for what unit tests cannot see: layout, the phone Filters button, the swipe strip, no-JS fallbacks.
// Run with bin/e2e (it checks the Ruby version first, as bin/check does). Specs are in e2e/.
import { defineConfig } from "@playwright/test";

// Not 4000: a dev server is often running there, and two servers on one port spoil each other's results.
const PORT = 4010;
const ORIGIN = `http://127.0.0.1:${PORT}`;

export default defineConfig({
  testDir: "e2e",
  fullyParallel: true,
  retries: 0,
  reporter: "list",
  use: { baseURL: ORIGIN },
  webServer: {
    // A strict build of the real site into its own folder (not _site, which the dev server writes), then served.
    command: `bundle exec jekyll serve --host 127.0.0.1 --port ${PORT} --no-watch --destination .e2e-site`,
    url: `${ORIGIN}/publications/`,
    reuseExistingServer: false,
    timeout: 120_000,
  },
});
