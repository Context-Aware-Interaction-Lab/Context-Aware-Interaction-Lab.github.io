// Without JavaScript the pages must still work: the whole list is there, and no control that needs a script is
// shown. (The Expand all button was once visible and dead here, because a component's display rule beat `hidden`.)
import { test, expect } from "./fixtures.js";

test.use({ javaScriptEnabled: false });

test.describe("Publications without JavaScript", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/publications/");
  });

  test("every paper is in the page and no script-only control is shown", async ({ page }) => {
    expect(await page.locator("li.publication-row").count()).toBe(39);
    await expect(page.locator(".pub-filters")).toBeHidden();
    await expect(page.locator(".pub-filters__toggle")).toBeHidden();
    await expect(page.locator(".pub-filters__clear")).toBeHidden();
    await expect(page.locator(".year-controls__all")).toBeHidden();
  });

  test("the years still fold by hand, the newest one open, and the banner reads normally", async ({ page }) => {
    expect(await page.locator("details.year[open]").count()).toBe(1);
    await page.locator("details.year:not([open]) > summary").first().click();
    expect(await page.locator("details.year[open]").count()).toBe(2);
    await expect(page.locator(".cta-banner--strip")).toBeVisible();
  });
});

test.describe("Research cards without JavaScript on a phone", () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });

  test("the swipe strip is plain CSS, so it still scrolls", async ({ page }) => {
    await page.goto("/research/");
    const strip = page.locator(".paper-cards").first();
    expect(await strip.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
    expect(await strip.evaluate(el => getComputedStyle(el).scrollSnapType)).toContain("mandatory");
  });
});
