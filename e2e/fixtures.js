import { test as base, expect } from "@playwright/test";

// The site's web fonts come from Google Fonts. Blocking them makes every run use the same fallback fonts, so the
// heights these specs measure do not depend on the network or on a font arriving late.
export const test = base.extend({
  page: async ({ page }, use) => {
    await page.route(/fonts\.(googleapis|gstatic)\.com/, route => route.abort());
    await use(page);
  },
});

export { expect };

// Every publication year is a closed <details> but the newest; measuring or finding rows needs them open.
export const openAllYears = page => page.evaluate(() => {
  document.querySelectorAll("details.year").forEach(fold => { fold.open = true; });
});

export const hasNoHorizontalScroll = page => page.evaluate(
  () => document.documentElement.scrollWidth <= document.documentElement.clientWidth,
);
