// Without JavaScript the pages must still work: the whole list is there, and no control that needs a script is
// shown. (The Expand all button was once visible and dead here, because a component's display rule beat `hidden`.)
import { test, expect } from "./fixtures.js";

test.use({ javaScriptEnabled: false });

test.describe("Publications without JavaScript", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/publications/");
  });

  test("every paper is in the page and no script-only control is shown", async ({ page }) => {
    expect(await page.locator("li.publication-row").count()).toBe(43);
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

test.describe("The Gallery slideshow without JavaScript", () => {
  test("shows the first album's cover as a plain still, and none of the script-only controls", async ({ page }) => {
    await page.goto("/gallery/");
    await expect(page.locator(".slideshow")).toBeHidden();
    await expect(page.locator(".slideshow__toggle")).toBeHidden();
    const still = page.locator(".slideshow-static");
    await expect(still).toBeVisible();
    await expect(still.locator("figcaption")).toHaveText("Lab day out in Chinatown");
    await expect.poll(() => still.locator("img").evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
    expect(await still.locator("a").getAttribute("href")).toBe("/assets/img/gallery/20260702-lab-day-out/01.jpg"); // the large photo, a plain link
  });
});

test.describe("The Gallery's album strips without JavaScript", () => {
  test("a year is still a scrolling, snapping strip, no arrow shows, and an opened card is a full-width slide", async ({ page }) => {
    await page.goto("/design-language/");
    const strip = page.locator("#gallery-2026 + .album-carousel .album-cards");
    expect(await strip.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true); // five cards run past the edge
    expect(await strip.evaluate(el => getComputedStyle(el).overflowX)).toBe("auto");
    expect(await strip.evaluate(el => getComputedStyle(el).scrollSnapType)).toContain("mandatory");
    await expect(page.locator(".album-carousel__btn:visible")).toHaveCount(0); // the arrows ship hidden and only the script shows them
    await strip.evaluate(el => el.scrollTo({ left: el.scrollWidth })); // and it really scrolls
    expect(await strip.evaluate(el => el.scrollLeft)).toBeGreaterThan(0);
    await strip.evaluate(el => el.scrollTo({ left: 0 }));
    const album = page.locator("#album-20261100-specimen-demos");
    await album.locator("> summary").click(); // the native <details> opens in place
    expect(await album.evaluate(el => el.open)).toBe(true);
    const [open, st] = await Promise.all([album.boundingBox(), strip.boundingBox()]);
    expect(open.width).toBeGreaterThan(st.width * 0.9); // an opened card takes the strip's whole width
    await expect(album.locator(".album__photo").first()).toBeVisible();
    await expect(page.locator("#figure-dialog")).toBeHidden();
  });

  test("the undated album is still listed last under Anytime, with no date", async ({ page }) => {
    await page.goto("/gallery/");
    await expect(page.locator(".gallery-year__title")).toHaveText(["2026", "Anytime"]);
    await expect(page.locator("#album-outtakes-and-oddities .album__meta")).toHaveText("1 photo");
  });
});
