// The Gallery's grid and lightbox, driven in a real browser on the specimen album at /design-language/ (the
// published site has no /gallery/ until the first album exists; the specimen is the same include fed publication
// figures). The album has 14 photos: 8 shown, 6 in a fold.
import { test, expect, hasNoHorizontalScroll } from "./fixtures.js";

const PAGE = "/design-language/#gallery-specimen";
const dialog = page => page.locator("#figure-dialog");
const tile = (page, n) => page.locator(".album__photo a").nth(n); // document order: the shown 8, then the folded 6

// Rows of the grid, by tile top edge, with every tile's box.
const rowsOf = page => page.evaluate(() => {
  const grid = document.querySelector(".album__grid");
  const g = grid.getBoundingClientRect();
  const rows = {};
  for (const li of grid.querySelectorAll(".album__photo")) {
    const b = li.getBoundingClientRect();
    (rows[Math.round(b.top)] ||= []).push({ left: b.left, right: b.right, height: b.height });
  }
  return { gridRight: g.right, gridLeft: g.left, rows: Object.values(rows) };
});

test.describe("Gallery album on a desktop", () => {
  test.beforeEach(async ({ page }) => { await page.goto(PAGE); });

  test("shows eight tiles and folds the other six behind a button", async ({ page }) => {
    expect(await page.locator(".album > .album__grid .album__photo").count()).toBe(8);
    const fold = page.locator("details.album__rest");
    expect(await fold.evaluate(el => el.open)).toBe(false);
    await expect(fold.locator("summary")).toHaveText("Show 6 more photos");
    await expect(fold.locator(".album__photo").first()).toBeHidden();
    await fold.locator("summary").click();
    await expect(fold.locator(".album__photo").first()).toBeVisible();
  });

  test("rows are justified: every row but the last fills the grid edge to edge, all one height", async ({ page }) => {
    const { gridLeft, gridRight, rows } = await rowsOf(page);
    expect(rows.length).toBeGreaterThanOrEqual(2);
    for (const row of rows) row.forEach(t => expect(Math.round(t.height)).toBe(220));
    for (const row of rows.slice(0, -1)) {
      expect(Math.round(Math.min(...row.map(t => t.left)))).toBe(Math.round(gridLeft));
      expect(Math.abs(Math.max(...row.map(t => t.right)) - gridRight)).toBeLessThanOrEqual(1.5);
    }
    // the last row keeps its natural size instead of stretching across the page
    const last = rows[rows.length - 1];
    if (rows.length > 1 && last.length < rows[0].length) {
      expect(Math.max(...last.map(t => t.right))).toBeLessThan(gridRight - 40);
    }
  });

  test("a tile opens the lightbox on that photo, with a counter and both steps", async ({ page }) => {
    await tile(page, 2).click();
    await expect(dialog(page)).toBeVisible();
    await expect(page.locator(".figure-dialog__count")).toHaveText("3 / 14");
    await expect(page.locator(".figure-dialog__prev")).toBeVisible();
    await expect(page.locator(".figure-dialog__next")).toBeVisible();
    await expect(page.locator(".figure-dialog__title")).toHaveText("Specimen album");
    const img = page.locator(".figure-dialog__stage img");
    expect(await img.getAttribute("src")).toMatch(/publications\/eacl26-blend-vis\.jpg$/);
    await expect(page.locator(".figure-dialog__caption")).toContainText("BLEnD-Vis");
  });

  test("arrow keys and the buttons step through, wrapping at both ends, and show a caption and credit", async ({ page }) => {
    const count = page.locator(".figure-dialog__count");
    await tile(page, 0).click();
    await expect(count).toHaveText("1 / 14");
    await page.keyboard.press("ArrowRight");
    await expect(count).toHaveText("2 / 14");
    await expect(page.locator(".figure-dialog__caption")).toContainText("much wider than it is tall"); // the caption, not the alt
    await page.keyboard.press("ArrowLeft");
    await page.keyboard.press("ArrowLeft");
    await expect(count).toHaveText("14 / 14"); // wrapped back past the first
    await page.locator(".figure-dialog__next").click();
    await expect(count).toHaveText("1 / 14");
    await page.locator(".figure-dialog__prev").click();
    await expect(count).toHaveText("14 / 14");
    for (let i = 0; i < 5; i++) await page.keyboard.press("ArrowLeft"); // 14 -> 9 is the credited photo
    await expect(count).toHaveText("9 / 14");
    await expect(page.locator(".figure-dialog__credit")).toHaveText("Photo: CAILab");
  });

  test("the stage keeps one size from photo to photo, so the dialog does not jump", async ({ page }) => {
    await tile(page, 0).click();
    const stage = page.locator(".figure-dialog__stage");
    const first = await stage.boundingBox();
    await page.keyboard.press("ArrowRight"); // a 1600x640 photo after a 1600x963 one
    await expect(page.locator(".figure-dialog__count")).toHaveText("2 / 14");
    const second = await stage.boundingBox();
    expect(Math.round(second.height)).toBe(Math.round(first.height));
    expect(Math.round(second.width)).toBe(Math.round(first.width));
  });

  test("stepping into the fold opens it, and Escape closes the dialog with focus on a visible tile", async ({ page }) => {
    await tile(page, 0).click();
    await page.keyboard.press("ArrowLeft"); // photo 14, in the folded part
    await expect(page.locator(".figure-dialog__count")).toHaveText("14 / 14");
    expect(await page.locator("details.album__rest").evaluate(el => el.open)).toBe(true);
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
    await expect(tile(page, 13)).toBeFocused();
  });

  test("Escape from the first photo returns focus to the tile that opened it", async ({ page }) => {
    await tile(page, 4).click();
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
    await expect(tile(page, 4)).toBeFocused();
  });

  test("arrow keys do nothing once the dialog is closed", async ({ page }) => {
    await tile(page, 0).click();
    await page.keyboard.press("Escape");
    await page.keyboard.press("ArrowRight");
    await expect(dialog(page)).toBeHidden();
  });
});

test.describe("Publication figures still open alone", () => {
  test("no steps, no counter, and the dark photo stage is not used", async ({ page }) => {
    await page.goto("/publications/");
    await page.locator("li.publication-row[data-figure] .publication-row__figure").first().click();
    await expect(dialog(page)).toBeVisible();
    await expect(page.locator(".figure-dialog__nav")).toBeHidden();
    expect(await dialog(page).evaluate(el => el.classList.contains("is-grouped"))).toBe(false);
    await page.keyboard.press("ArrowRight");
    await expect(dialog(page)).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
  });
});

test.describe("Gallery album on a phone", () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });
  test.beforeEach(async ({ page }) => { await page.goto(PAGE); });

  test("tiles are 140px tall, rows still fill the width and the page does not scroll sideways", async ({ page }) => {
    const { gridLeft, gridRight, rows } = await rowsOf(page);
    for (const row of rows) row.forEach(t => expect(Math.round(t.height)).toBe(140));
    for (const row of rows.slice(0, -1)) {
      expect(Math.abs(Math.max(...row.map(t => t.right)) - gridRight)).toBeLessThanOrEqual(1.5);
      expect(Math.round(Math.min(...row.map(t => t.left)))).toBe(Math.round(gridLeft));
    }
    expect(await hasNoHorizontalScroll(page)).toBe(true);
  });

  test("the lightbox fills the screen, its buttons are at least 44px, and nothing scrolls sideways", async ({ page }) => {
    await tile(page, 0).click();
    await expect(dialog(page)).toBeVisible();
    const box = await dialog(page).boundingBox();
    expect(Math.round(box.width)).toBe(390);
    for (const sel of [".figure-dialog__prev", ".figure-dialog__next", ".figure-dialog__close"]) {
      const b = await page.locator(sel).boundingBox();
      expect(b.width, sel).toBeGreaterThanOrEqual(44);
      expect(b.height, sel).toBeGreaterThanOrEqual(44);
    }
    expect(await hasNoHorizontalScroll(page)).toBe(true);
  });

  test("a swipe left steps forward, a swipe right steps back, and a short drag does nothing", async ({ page }) => {
    await tile(page, 0).click();
    const count = page.locator(".figure-dialog__count");
    await expect(count).toHaveText("1 / 14");
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
    await expect(count).toHaveText("2 / 14");
    await drag(80, 300);
    await expect(count).toHaveText("1 / 14");
    await drag(200, 170); // 30px: below the threshold
    await expect(count).toHaveText("1 / 14");
  });
});

test.describe("Gallery album without JavaScript", () => {
  test.use({ javaScriptEnabled: false });

  test("every tile is a plain link to its large image and the fold still opens by hand", async ({ page }) => {
    await page.goto("/design-language/");
    const hrefs = await page.locator(".album__photo a").evaluateAll(as => as.map(a => a.getAttribute("href")));
    expect(hrefs).toHaveLength(14);
    hrefs.forEach(h => expect(h).toMatch(/^\/assets\/img\/publications\/[a-z0-9-]+\.jpg$/));
    await expect(dialog(page)).toBeHidden();
    await page.locator("details.album__rest > summary").click();
    await expect(page.locator("details.album__rest .album__photo").first()).toBeVisible();
    await expect(page.locator(".figure-dialog__nav")).toBeHidden();
  });
});

// The real page, once the first album is in gallery.yml: one album of 32 photos (8 shown, 24 folded), one category,
// so no chips.
test.describe("The Gallery page", () => {
  test("lists the album under its year, loads its photos and opens the lightbox on one", async ({ page }) => {
    await page.goto("/gallery/");
    await expect(page.locator("h1")).toHaveText("Gallery");
    await expect(page.locator(".gallery-year__title")).toHaveText("2026");
    await expect(page.locator(".album__title")).toHaveText("Lab day out in Chinatown");
    expect(await page.locator(".album__photo").count()).toBe(32);
    await expect(page.locator("details.album__rest > summary")).toHaveText("Show 24 more photos");
    await expect(page.locator(".gallery-filters")).toBeHidden(); // one category: nothing to choose between
    // the first row of thumbnails really loaded (a wrong path would leave a broken image)
    await expect.poll(() => page.locator(".album > .album__grid img").evaluateAll(
      imgs => imgs.slice(0, 4).every(i => i.complete && i.naturalWidth > 0))).toBe(true);
    await tile(page, 1).click(); // a portrait photo
    await expect(page.locator(".figure-dialog__count")).toHaveText("2 / 32");
    await expect.poll(() => page.locator(".figure-dialog__stage img").evaluate(i => i.complete && i.naturalHeight > i.naturalWidth)).toBe(true);
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
