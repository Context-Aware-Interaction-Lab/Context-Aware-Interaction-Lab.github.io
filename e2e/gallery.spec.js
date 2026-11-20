// The Gallery's album cards and lightbox, driven in a real browser on the seven specimen albums at /design-language/
// (the same includes the real page uses, fed publication figures). 2026 holds five: 20261100-specimen-demos (14 photos,
// demos), 20261000-specimen-long (2, outreach, a very long title and place), 20260912-specimen-short (1, demos),
// 20260800-specimen-no-place (2, lab life) and 20260600-specimen-conferences (3, conferences); 2025 holds
// 20250900-specimen-single (1, lab life); specimen-undated (2, lab life) is tied to no year. The strips, the lens and the
// equal card size are in carousel.spec.js; the real /gallery/ is checked at the end of this file.
import { test, expect, hasNoHorizontalScroll } from "./fixtures.js";

const PAGE = "/design-language/";
const dialog = page => page.locator("#figure-dialog");
const card = (page, slug) => page.locator(`#album-${slug} > summary`);
const sheetTile = (page, n) => page.locator(".album__sheet button").nth(n);
const count = page => page.locator(".figure-dialog__count");

// Rows of a justified grid, by tile top edge, with every tile's box.
const rowsOf = (page, selector) => page.evaluate(sel => {
  const grid = document.querySelector(sel);
  const g = grid.getBoundingClientRect();
  const rows = {};
  for (const li of grid.querySelectorAll(".album__photo")) {
    const b = li.getBoundingClientRect();
    (rows[Math.round(b.top)] ||= []).push({ left: b.left, right: b.right, height: b.height });
  }
  return { gridRight: g.right, gridLeft: g.left, rows: Object.values(rows) };
}, selector);

test.describe("Album cards on a desktop", () => {
  test.beforeEach(async ({ page }) => { await page.goto(PAGE); });

  test("albums sit on one strip per year, newest first, the undated one last under Anytime, each cover 4:3", async ({ page }) => {
    await expect(page.locator(".gallery-year__title")).toHaveText(["2026", "2025", "Anytime"]);
    const ids = await page.locator("details.album").evaluateAll(els => els.map(e => e.id));
    expect(ids).toEqual([
      "album-20261100-specimen-demos", "album-20261000-specimen-long", "album-20260912-specimen-short",
      "album-20260800-specimen-no-place", "album-20260600-specimen-conferences", "album-20250900-specimen-single", "album-specimen-undated",
    ]);
    const tops = await page.locator("#gallery-2026 + .album-carousel .album__card").evaluateAll(els => els.map(e => Math.round(e.offsetTop)));
    expect(new Set(tops).size).toBe(1); // a year is one strip, one row, however many albums it has
    const cover = await page.locator(".album__cover").first().boundingBox();
    expect(Math.abs(cover.height / cover.width - 0.75)).toBeLessThan(0.05); // 4:3, give or take the lens
  });

  test("the cards show covers only: the photos stay inside closed albums, which do not open", async ({ page }) => {
    expect(await page.locator("details.album[open]").count()).toBe(0);
    await expect(page.locator(".album__body .album__photo").first()).toBeHidden();
    await card(page, "20261100-specimen-demos").click();
    await expect(dialog(page)).toBeVisible();
    expect(await page.locator("details.album[open]").count()).toBe(0); // the click opened the lightbox, not the card
  });

  test("a card opens the lightbox on the album's contact sheet: facts, summary and every photo", async ({ page }) => {
    await card(page, "20261100-specimen-demos").click();
    await expect(dialog(page)).toBeVisible();
    expect(await dialog(page).evaluate(el => el.classList.contains("is-sheet"))).toBe(true);
    await expect(page.locator(".figure-dialog__title")).toHaveText("Specimen album");
    await expect(page.locator(".album__intro .album__meta")).toHaveText("November 2026 · Singapore · 14 photos");
    await expect(page.locator(".album__intro .album__summary")).toContainText("Publication figures standing in for photos");
    expect(await page.locator(".album__sheet button").count()).toBe(14);
    await expect(page.locator(".figure-dialog__nav")).toBeHidden();
    expect(new URL(page.url()).hash).toBe("#album-20261100-specimen-demos");
  });

  test("the sheet's rows are justified: all but the last fill the width, all one 150px height", async ({ page }) => {
    await card(page, "20261100-specimen-demos").click();
    await expect.poll(() => page.locator(".album__sheet img").evaluateAll(imgs => imgs.slice(0, 4).every(i => i.complete && i.naturalWidth > 0))).toBe(true);
    const { gridLeft, gridRight, rows } = await rowsOf(page, ".album__sheet");
    expect(rows.length).toBeGreaterThanOrEqual(3);
    for (const row of rows) row.forEach(t => expect(Math.round(t.height)).toBe(150));
    for (const row of rows.slice(0, -1)) {
      expect(Math.round(Math.min(...row.map(t => t.left)))).toBe(Math.round(gridLeft));
      expect(Math.abs(Math.max(...row.map(t => t.right)) - gridRight)).toBeLessThanOrEqual(1.5);
    }
  });

  test("a tile opens that photo; All photos goes back to the sheet and lands on the tile just viewed", async ({ page }) => {
    await card(page, "20261100-specimen-demos").click();
    await sheetTile(page, 2).click();
    await expect(count(page)).toHaveText("3 / 14");
    expect(await dialog(page).evaluate(el => el.classList.contains("is-grouped"))).toBe(true);
    await expect(page.locator(".figure-dialog__all")).toBeFocused(); // the tile just left the page; focus stayed in the dialog
    expect(await page.locator(".figure-dialog__stage img").getAttribute("src")).toMatch(/publications\/eacl26-blend-vis\.jpg$/);
    await expect(page.locator(".figure-dialog__caption")).toContainText("BLEnD-Vis");
    await page.locator(".figure-dialog__all").click();
    expect(await dialog(page).evaluate(el => el.classList.contains("is-sheet"))).toBe(true);
    await expect(sheetTile(page, 2)).toBeFocused();
  });

  test("arrow keys and the buttons step through, wrapping at both ends, with a caption and a credit", async ({ page }) => {
    await card(page, "20261100-specimen-demos").click();
    await sheetTile(page, 0).click();
    await expect(count(page)).toHaveText("1 / 14");
    await page.keyboard.press("ArrowRight");
    await expect(count(page)).toHaveText("2 / 14");
    await expect(page.locator(".figure-dialog__caption")).toContainText("much wider than it is tall"); // the caption, not the alt
    await page.keyboard.press("ArrowLeft");
    await page.keyboard.press("ArrowLeft");
    await expect(count(page)).toHaveText("14 / 14");
    await page.locator(".figure-dialog__next").click();
    await expect(count(page)).toHaveText("1 / 14");
    await page.locator(".figure-dialog__prev").click();
    await expect(count(page)).toHaveText("14 / 14");
    for (let i = 0; i < 5; i++) await page.keyboard.press("ArrowLeft"); // 14 -> 9 is the credited photo
    await expect(count(page)).toHaveText("9 / 14");
    await expect(page.locator(".figure-dialog__credit")).toHaveText("Photo: CAILab");
  });

  test("the stage keeps one size from photo to photo, so the dialog does not jump", async ({ page }) => {
    await card(page, "20261100-specimen-demos").click();
    await sheetTile(page, 0).click();
    const stage = page.locator(".figure-dialog__stage");
    const first = await stage.boundingBox();
    await page.keyboard.press("ArrowRight"); // a 1600x640 photo after a 1600x963 one
    await expect(count(page)).toHaveText("2 / 14");
    const second = await stage.boundingBox();
    expect(Math.round(second.height)).toBe(Math.round(first.height));
    expect(Math.round(second.width)).toBe(Math.round(first.width));
  });

  test("arrow keys do nothing on the sheet; Escape closes, focus returns to the card and the hash is cleared", async ({ page }) => {
    await card(page, "20261100-specimen-demos").click();
    await page.keyboard.press("ArrowRight");
    expect(await dialog(page).evaluate(el => el.classList.contains("is-sheet"))).toBe(true);
    await expect(count(page)).toHaveText("");
    await sheetTile(page, 5).click();
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
    await expect(card(page, "20261100-specimen-demos")).toBeFocused();
    expect(new URL(page.url()).hash).toBe("");
    await page.keyboard.press("ArrowRight");
    await expect(dialog(page)).toBeHidden();
  });

  test("a card opens from the keyboard", async ({ page }) => {
    await card(page, "20260600-specimen-conferences").focus();
    await page.keyboard.press("Enter");
    await expect(dialog(page)).toBeVisible();
    await expect(page.locator(".figure-dialog__title")).toHaveText("Specimen: a second album");
    expect(await page.locator(".album__sheet button").count()).toBe(3);
    await sheetTile(page, 0).click();
    await page.keyboard.press("ArrowLeft"); // wraps within three
    await expect(count(page)).toHaveText("3 / 3");
  });

  test("an album of one photo skips the sheet: straight to the photo, no steps, no All photos", async ({ page }) => {
    await card(page, "20250900-specimen-single").click();
    await expect(dialog(page)).toBeVisible();
    expect(await dialog(page).evaluate(el => el.classList.contains("is-sheet"))).toBe(false);
    expect(await page.locator(".album__sheet").count()).toBe(0);
    await expect(page.locator(".figure-dialog__stage img")).toBeVisible();
    await expect(page.locator(".figure-dialog__nav")).toBeHidden();
    await expect(page.locator(".figure-dialog__all")).toBeHidden();
    await page.keyboard.press("Escape");
    await expect(card(page, "20250900-specimen-single")).toBeFocused();
  });
});

test.describe("Category chips and deep links", () => {
  test("chips filter the cards, hide a year with none left, mirror to the address, and clear", async ({ page }) => {
    await page.goto(PAGE);
    const chips = page.locator('.chip[data-filter="category"]');
    await expect(chips).toHaveCount(4);
    await expect(page.locator(".gallery-filters")).toBeVisible();
    await page.locator('.chip[data-value="demos"]').click();
    await expect(page.locator("details.album:visible")).toHaveCount(2); // the demos album and Short
    await expect(page.locator(".gallery-year__title:visible")).toHaveText(["2026"]); // 2025 and Anytime hold only lab-life albums
    await expect(page.locator(".gallery-filters__status")).toHaveText("Showing 2 of 7 albums");
    expect(new URL(page.url()).search).toBe("?category=demos");
    await page.locator('.chip[data-value="lab-life"]').click(); // chips add up
    await expect(page.locator("details.album:visible")).toHaveCount(5);
    await expect(page.locator(".gallery-year__title:visible")).toHaveText(["2026", "2025", "Anytime"]);
    await page.locator(".gallery-filters__clear").click();
    await expect(page.locator("details.album:visible")).toHaveCount(7);
    expect(new URL(page.url()).search).toBe("");
  });

  test("/#album-<slug> opens that album on load", async ({ page }) => {
    await page.goto(`${PAGE}#album-20260600-specimen-conferences`);
    await expect(dialog(page)).toBeVisible();
    await expect(page.locator(".figure-dialog__title")).toHaveText("Specimen: a second album");
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
    // Nothing was focused before the dialog opened, so the browser has nothing to restore: the script must focus the card.
    await expect(card(page, "20260600-specimen-conferences")).toBeFocused();
    expect(new URL(page.url()).hash).toBe("");
  });

  test("a link to an album the filter hides clears the filter first, then opens the album", async ({ page }) => {
    await page.goto(`${PAGE}?category=demos#album-20260600-specimen-conferences`);
    await expect(dialog(page)).toBeVisible();
    await expect(page.locator(".figure-dialog__title")).toHaveText("Specimen: a second album");
    await expect(page.locator("details.album[hidden]")).toHaveCount(0);
    await page.keyboard.press("Escape");
    await expect(page.locator("details.album:visible")).toHaveCount(7);
  });
});

test.describe("Publication figures still open alone", () => {
  test("no steps, no counter, no All photos, and the dark photo stage is not used", async ({ page }) => {
    await page.goto("/publications/");
    await page.locator("li.publication-row[data-figure] .publication-row__figure").first().click();
    await expect(dialog(page)).toBeVisible();
    await expect(page.locator(".figure-dialog__nav")).toBeHidden();
    expect(await dialog(page).evaluate(el => el.classList.contains("is-grouped") || el.classList.contains("is-sheet"))).toBe(false);
    await page.keyboard.press("ArrowRight");
    await expect(dialog(page)).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
  });
});

test.describe("Album cards on a phone", () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  test.beforeEach(async ({ page }) => { await page.goto(PAGE); });

  test("a year is a swipeable strip with the next card peeking in, and the page does not scroll sideways", async ({ page }) => {
    const strip = page.locator("#gallery-2026 + .album-carousel .album-cards");
    expect(await strip.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
    expect(await strip.evaluate(el => getComputedStyle(el).scrollSnapType)).toContain("mandatory");
    const cards = await strip.locator(".album__card").evaluateAll(els => els.slice(0, 2).map(e => { const b = e.getBoundingClientRect(); return { left: Math.round(b.left), right: Math.round(b.right), width: Math.round(e.offsetWidth) }; }));
    expect(cards[0].width).toBe(280); // min(72vw, 280px) at 390px
    expect(cards[1].left).toBeLessThan(390); // the second card starts on screen...
    expect(cards[1].right).toBeGreaterThan(390); // ...and runs off it, so it is clear that there is more
    await expect(page.locator(".album-carousel__btn:visible")).toHaveCount(0); // a phone swipes, so no arrows over the photos
    expect(await hasNoHorizontalScroll(page)).toBe(true);
  });

  test("the sheet fills the screen with 110px rows; a tile opens a photo; the buttons are at least 44px", async ({ page }) => {
    await card(page, "20261100-specimen-demos").click();
    await expect(dialog(page)).toBeVisible();
    expect(Math.round((await dialog(page).boundingBox()).width)).toBe(390);
    const { rows } = await rowsOf(page, ".album__sheet");
    for (const row of rows) row.forEach(t => expect(Math.round(t.height)).toBe(110));
    expect(await hasNoHorizontalScroll(page)).toBe(true);
    await sheetTile(page, 0).click();
    await expect(count(page)).toHaveText("1 / 14");
    for (const sel of [".figure-dialog__prev", ".figure-dialog__next", ".figure-dialog__close", ".figure-dialog__all"]) {
      const b = await page.locator(sel).boundingBox();
      expect(b.height, sel).toBeGreaterThanOrEqual(44);
      if (sel !== ".figure-dialog__all") expect(b.width, sel).toBeGreaterThanOrEqual(44);
    }
  });

  test("a swipe left steps forward, a swipe right steps back, and a short drag does nothing", async ({ page }) => {
    await card(page, "20261100-specimen-demos").click();
    await sheetTile(page, 0).click();
    await expect(count(page)).toHaveText("1 / 14");
    const box = await page.locator(".figure-dialog__stage").boundingBox();
    const y = box.y + box.height / 2;
    const cdp = await page.context().newCDPSession(page);
    const drag = async (from, to) => {
      await cdp.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: from, y }] });
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: (from + to) / 2, y }] });
      await cdp.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: to, y }] });
      await cdp.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    };
    await drag(300, 80);
    await expect(count(page)).toHaveText("2 / 14");
    await drag(80, 300);
    await expect(count(page)).toHaveText("1 / 14");
    await drag(200, 170); // 30px: below the threshold
    await expect(count(page)).toHaveText("1 / 14");
  });
});

test.describe("Album cards without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  test("a card opens in place into a full-width grid of plain links; no script-only control shows", async ({ page }) => {
    await page.goto(PAGE);
    await expect(page.locator(".gallery-filters")).toBeHidden();
    const album = page.locator("#album-20261100-specimen-demos");
    await album.locator("> summary").click();
    expect(await album.evaluate(el => el.open)).toBe(true);
    await expect(dialog(page)).toBeHidden();
    const hrefs = await album.locator(".album__photo a").evaluateAll(as => as.map(a => a.getAttribute("href")));
    expect(hrefs).toHaveLength(14);
    hrefs.forEach(h => expect(h).toMatch(/^\/assets\/img\/publications\/[a-z0-9-]+\.jpg$/));
    await expect(album.locator(".album__photo").first()).toBeVisible();
    const open = await album.boundingBox();
    const container = await page.locator("#gallery-specimen .container").boundingBox();
    expect(open.width).toBeGreaterThan(container.width * 0.9); // an opened card takes the whole row
    await expect(album.locator(".album__link, .album__summary").first()).toBeVisible();
  });
});

// The real page: three albums. 2026, newest first by name: 20260702-lab-day-out (32 photos), 20260413-chi26-barcelona
// (9); then, tied to no year and under "Anytime": outtakes-and-oddities (1, the catch-all). Two categories, so the
// category chips show.
test.describe("The Gallery page", () => {
  test("lists the albums as cards under their years, newest first, with their covers loaded", async ({ page }) => {
    await page.goto("/gallery/");
    await expect(page.locator("h1")).toHaveText("Gallery");
    await expect(page.locator(".gallery-year__title")).toHaveText(["2026", "Anytime"]); // the catch-all is tied to no year
    await expect(page.locator(".album__title")).toHaveText(["Lab day out in Chinatown", "CHI 2026 in Barcelona", "Outtakes & Oddities"]);
    await expect(page.locator(".album__meta").nth(0)).toContainText("32 photos");
    await expect(page.locator(".album__meta").nth(1)).toContainText("Barcelona, Spain · 9 photos");
    await expect(page.locator(".album__meta").nth(2)).toHaveText("1 photo"); // no date and no place: just the count
    await expect.poll(() => page.locator(".album__cover").evaluateAll(imgs => imgs.every(i => i.complete && i.naturalWidth > 0))).toBe(true);
  });

  test("the category chips show for the two categories in use, filter the cards, and clear", async ({ page }) => {
    await page.goto("/gallery/");
    const chips = page.locator(".gallery-filters .chip");
    await expect(page.locator(".gallery-filters")).toBeVisible();
    await expect(chips).toHaveText(["Conferences 1", "Lab life 2"]);
    await chips.nth(0).click(); // Conferences
    await expect(chips.nth(0)).toHaveAttribute("aria-pressed", "true");
    await expect(page.locator("details.album:visible")).toHaveCount(1);
    await expect(page.locator("#album-20260413-chi26-barcelona")).toBeVisible();
    await expect(page.locator("#album-20260702-lab-day-out")).toBeHidden();
    await expect(page.locator(".gallery-year__title:visible")).toHaveText(["2026"]); // 2024 holds only a lab-life album
    await expect(page.locator(".gallery-filters__status")).toHaveText("Showing 1 of 3 albums");
    expect(new URL(page.url()).search).toBe("?category=conferences");
    await page.locator(".gallery-filters__clear").click();
    await expect(page.locator("details.album:visible")).toHaveCount(3);
    expect(new URL(page.url()).search).toBe("");
  });

  test("the day-out album opens on its contact sheet, then a portrait photo", async ({ page }) => {
    await page.goto("/gallery/");
    await card(page, "20260702-lab-day-out").click();
    expect(await page.locator(".album__sheet button").count()).toBe(32);
    await expect.poll(() => page.locator(".album__sheet img").evaluateAll(imgs => imgs.slice(0, 4).every(i => i.complete && i.naturalWidth > 0))).toBe(true);
    await sheetTile(page, 1).click(); // a portrait photo
    await expect(count(page)).toHaveText("2 / 32");
    await expect.poll(() => page.locator(".figure-dialog__stage img").evaluate(i => i.complete && i.naturalHeight > i.naturalWidth)).toBe(true);
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
  });

  test("the one-photo catch-all skips the contact sheet and opens straight on its photo", async ({ page }) => {
    await page.goto("/gallery/");
    await card(page, "outtakes-and-oddities").click();
    await expect(dialog(page)).toBeVisible();
    expect(await dialog(page).evaluate(el => el.classList.contains("is-sheet"))).toBe(false);
    await expect(page.locator(".figure-dialog__title")).toHaveText("Outtakes & Oddities"); // the ampersand survives
    await expect(page.locator(".figure-dialog__nav")).toBeHidden(); // one photo: nothing to step through
    await expect.poll(() => page.locator(".figure-dialog__stage img").evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
  });

  test("the CHI album opens its nine photos, in order, with the poster photos upright", async ({ page }) => {
    await page.goto("/gallery/");
    await card(page, "20260413-chi26-barcelona").click();
    expect(await page.locator(".album__sheet button").count()).toBe(9);
    await expect(page.locator(".figure-dialog__title")).toHaveText("CHI 2026 in Barcelona");
    await sheetTile(page, 4).click(); // 05: a poster photo, stored sideways and turned upright by bin/figure
    await expect(count(page)).toHaveText("5 / 9");
    await expect.poll(() => page.locator(".figure-dialog__stage img").evaluate(i => i.complete && i.naturalHeight > i.naturalWidth)).toBe(true);
    await expect(page.locator(".figure-dialog__caption")).toContainText("Taxonomy of Human-MLLM Interaction");
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
  });

  test("the nav lists Gallery just before Code, and it is the current page there", async ({ page }) => {
    await page.goto("/gallery/");
    const links = await page.locator("#nav-links a").allTextContents();
    expect(links.slice(-2)).toEqual(["Gallery", "Code"]);
    await expect(page.locator('#nav-links a[aria-current="page"]')).toHaveText("Gallery");
  });
});
