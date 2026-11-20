// The slideshow that opens /gallery/ (assets/js/gallery-slideshow.js), on the real page, whose albums are all in its pool.
// Which photo (so which album) is shown first is random, so these specs read the shown photo's own album from the page
// and never assume one.
// Time is Playwright's fake clock: the 6 s dwell is crossed with clock.runFor, so no test waits six real seconds. The
// CSS fade itself still runs in real time (a fake clock does not slow transitions), which is why the checks on it
// read the computed transition and the layers' classes rather than a pixel mid-way.
import { test, expect, hasNoHorizontalScroll } from "./fixtures.js";

const PAGE = "/gallery/";
const root = page => page.locator(".slideshow");
const activeImg = page => page.locator(".slideshow__layer.is-active .slideshow__img");
const src = page => activeImg(page).getAttribute("src");
const idle = page => expect(page.locator(".slideshow__layer.is-leaving")).toHaveCount(0);
const dialog = page => page.locator("#figure-dialog");
// The photo on show, and the album it belongs to, read from the page's own photo links.
const current = page => page.evaluate(() => {
  const src = document.querySelector(".slideshow__layer.is-active .slideshow__img").getAttribute("src");
  const a = [...document.querySelectorAll("a[data-figure]")].find(x => x.getAttribute("href") === src);
  const album = document.getElementById(a.dataset.group);
  return {
    src, group: a.dataset.group, title: a.dataset.title,
    when: album.querySelector(".album__meta time").textContent,
    size: document.querySelectorAll(`a[data-figure][data-group="${a.dataset.group}"]`).length,
  };
});
const poolOf = page => page.locator('a[data-figure][data-group^="album-"]').evaluateAll(as => as.map(a => a.getAttribute("href")));

// Open the page with the clock installed, wait for the first photo to be fully in, and stop time there.
async function open(page) {
  await page.clock.install({ time: new Date("2026-11-20T08:00:00") });
  await page.goto(PAGE);
  await expect(root(page)).toBeVisible();
  await expect(activeImg(page)).toHaveCount(1);
  await expect.poll(() => activeImg(page).evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
  await idle(page);
  await page.clock.pauseAt(new Date("2026-11-20T08:00:05"));
}

// Cross the dwell (6 s) in one-second steps until the photo changes, and return the new source.
async function untilChange(page, from) {
  await expect.poll(async () => {
    await page.clock.runFor(1000);
    return src(page);
  }, { timeout: 15_000 }).not.toBe(from);
  return src(page);
}

// Fake time marches on while nothing is due; this is "a long time passes and the photo is still the same".
async function staysFor(page, ms) {
  const before = await src(page);
  await page.clock.runFor(ms);
  await page.waitForTimeout(300); // a step would need a decode and a swap: give one the chance to happen
  expect(await src(page)).toBe(before);
}

test.describe("The slideshow on a desktop", () => {
  test("opens on one photo from the album, named and dated, and shows it whole", async ({ page }) => {
    await open(page);
    const pool = await poolOf(page);
    expect(pool).toContain(await src(page));
    const shown = await current(page);
    await expect(root(page).locator(".slideshow__album")).toHaveText(shown.title);
    await expect(root(page).locator(".slideshow__album")).toHaveAttribute("href", `#${shown.group}`);
    await expect(root(page).locator(".slideshow__when")).toHaveText(shown.when);
    expect(await activeImg(page).evaluate(i => getComputedStyle(i).objectFit)).toBe("contain"); // never cropped
    await expect(root(page)).toHaveAttribute("aria-roledescription", "carousel");
    await expect(page.locator(".slideshow__layer.is-active")).toHaveAttribute("aria-hidden", "false");
    expect(await page.locator(".slideshow__layer:not(.is-active)").getAttribute("aria-hidden")).toBe("true");
  });

  test("the pool holds every photo of every album", async ({ page }) => {
    await open(page);
    const groups = await page.locator('a[data-figure][data-group^="album-"]').evaluateAll(as => as.map(a => a.dataset.group));
    expect(groups.length).toBe((await poolOf(page)).length);
    expect(new Set(groups).size).toBe(await page.locator("details.album").count()); // each album is in it
    expect(new Set(groups).size).toBeGreaterThan(1); // so the pick really is across albums
  });

  test("after the dwell it crossfades to a different photo of the pool, the old one held opaque beneath", async ({ page }) => {
    await open(page);
    const pool = await poolOf(page);
    const first = await src(page);
    const second = await untilChange(page, first);
    expect(second).not.toBe(first);
    expect(pool).toContain(second);
    expect(await page.locator(".slideshow__layer.is-active").evaluate(l => getComputedStyle(l).transitionDuration)).toBe("1.2s");
    await expect(page.locator(".slideshow__layer.is-leaving")).toHaveCount(1); // fading in on top of it
    expect(await page.locator(".slideshow__layer.is-leaving").evaluate(l => getComputedStyle(l).opacity)).toBe("1");
    await idle(page); // the fade ends and the old layer is released
  });

  test("Next shows every photo once before any repeats, and the stage never changes size", async ({ page }) => {
    await page.addStyleTag({ content: ".slideshow{--fade:1ms !important}" }); // 32 steps: do not wait on 32 fades
    await open(page);
    const pool = await poolOf(page);
    const seen = [await src(page)];
    const heights = new Set();
    const orientations = new Set();
    for (let n = 1; n < pool.length; n++) {
      await idle(page);
      await root(page).locator(".slideshow__next").click();
      await expect.poll(() => src(page)).not.toBe(seen[seen.length - 1]);
      seen.push(await src(page));
      await expect.poll(() => activeImg(page).evaluate(i => i.complete && i.naturalWidth > 0)).toBe(true);
      const box = await root(page).locator(".slideshow__stage").boundingBox();
      heights.add(Math.round(box.height));
      orientations.add(await activeImg(page).evaluate(i => (i.naturalHeight > i.naturalWidth ? "portrait" : "landscape")));
    }
    expect(new Set(seen).size).toBe(pool.length); // no repeat inside a round, and every photo of every album comes up
    expect([...seen].sort()).toEqual([...pool].sort()); // and nothing outside the pool
    expect(heights.size).toBe(1);
    expect([...orientations].sort()).toEqual(["landscape", "portrait"]); // the check covered both shapes
  });

  test("Previous goes back through what was shown, and does nothing at the start", async ({ page }) => {
    await open(page);
    const prev = root(page).locator(".slideshow__prev");
    await expect(prev).toHaveAttribute("aria-disabled", "true");
    const first = await src(page);
    await root(page).locator(".slideshow__next").click();
    await expect.poll(() => src(page)).not.toBe(first);
    await idle(page);
    await expect(prev).toHaveAttribute("aria-disabled", "false");
    expect(await page.locator(".slideshow__layer.is-active").evaluate(l => getComputedStyle(l).transitionDuration)).toBe("0.35s");
    await prev.click();
    await expect.poll(() => src(page)).toBe(first);
    await idle(page);
    await prev.click({ force: true }); // already at the start: aria-disabled, but still pressable
    await page.waitForTimeout(300);
    expect(await src(page)).toBe(first);
  });

  test("Pause stops it for as long as it is paused, and Play starts it again", async ({ page }) => {
    await open(page);
    const first = await src(page);
    const toggle = root(page).locator(".slideshow__toggle");
    await expect(toggle).toHaveText("Pause");
    await toggle.click();
    await expect(toggle).toHaveText("Play");
    await expect(toggle).toHaveAccessibleName("Play slideshow");
    await page.mouse.move(0, 0); // the pointer is not what holds it
    await staysFor(page, 30_000);
    await toggle.click();
    await expect(toggle).toHaveText("Pause");
    await page.mouse.move(0, 0);
    expect(await untilChange(page, first)).not.toBe(first);
  });

  test("a mouse over it holds it, and moving away lets it go on", async ({ page }) => {
    await open(page);
    const first = await src(page);
    await root(page).hover();
    await staysFor(page, 30_000);
    await page.mouse.move(0, 0);
    expect(await untilChange(page, first)).not.toBe(first);
  });

  test("a keyboard user on a control holds it; leaving lets it go on", async ({ page }) => {
    await open(page);
    const first = await src(page);
    await page.keyboard.press("Tab"); // starts the page's keyboard modality, so focus below is focus-visible
    await root(page).locator(".slideshow__next").focus();
    await staysFor(page, 30_000);
    await page.locator("body").evaluate(() => document.activeElement.blur());
    expect(await untilChange(page, first)).not.toBe(first);
  });

  test("a hidden tab holds it", async ({ page }) => {
    await open(page);
    const first = await src(page);
    await page.evaluate(() => {
      Object.defineProperty(document, "hidden", { configurable: true, get: () => true });
      document.dispatchEvent(new Event("visibilitychange"));
    });
    await staysFor(page, 30_000);
    await page.evaluate(() => {
      Object.defineProperty(document, "hidden", { configurable: true, get: () => false });
      document.dispatchEvent(new Event("visibilitychange"));
    });
    expect(await untilChange(page, first)).not.toBe(first);
  });

  test("scrolled out of view it holds, and scrolling back lets it go on", async ({ page }) => {
    await open(page);
    const first = await src(page);
    await page.locator(".gallery-year").scrollIntoViewIfNeeded();
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    await expect.poll(() => root(page).evaluate(el => el.classList.contains("is-held"))).toBe(true);
    await staysFor(page, 30_000);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.mouse.move(0, 0);
    expect(await untilChange(page, first)).not.toBe(first);
  });

  test("pressing the photo opens the lightbox on that photo and holds it; closing returns focus and resumes", async ({ page }) => {
    await open(page);
    const first = await src(page);
    const shown = await current(page);
    await root(page).locator(".slideshow__photo").click();
    await expect(dialog(page)).toBeVisible();
    // the dialog writes an absolute URL, the page a relative one: compare the paths
    await expect.poll(() => dialog(page).locator(".figure-dialog__img").evaluate(i => new URL(i.src).pathname)).toBe(first);
    await expect(dialog(page).locator(".figure-dialog__count")).toHaveText(new RegExp(` / ${shown.size}$`)); // the shown photo's own album
    await staysFor(page, 30_000);
    await dialog(page).locator(".figure-dialog__close").click();
    await expect(dialog(page)).toBeHidden();
    await expect(root(page).locator(".slideshow__photo")).toBeFocused();
    await page.mouse.move(0, 0);
    expect(await untilChange(page, first)).not.toBe(first);
  });

  test("Escape from that lightbox returns focus to the photo, and stepping inside it does not move the return point", async ({ page }) => {
    await open(page);
    await root(page).locator(".slideshow__photo").click();
    await expect(dialog(page)).toBeVisible();
    await page.keyboard.press("ArrowRight");
    await page.keyboard.press("ArrowRight");
    await page.keyboard.press("Escape");
    await expect(dialog(page)).toBeHidden();
    await expect(root(page).locator(".slideshow__photo")).toBeFocused();
  });

  test("the caption link opens the album's contact sheet", async ({ page }) => {
    await open(page);
    const shown = await current(page);
    await root(page).locator(".slideshow__album").click();
    await expect(dialog(page)).toBeVisible();
    expect(await dialog(page).evaluate(el => el.classList.contains("is-sheet"))).toBe(true);
    await expect(page.locator(".figure-dialog__title")).toHaveText(shown.title);
    await expect(page.locator(".album__sheet button")).toHaveCount(shown.size);
  });

  // At 1280x720 the banner, nav and page header take about 330px. An uncapped 70vh stage pushed the caption and Pause
  // below the fold (seen at 900px tall); now photo, caption and controls arrive on one screen, so Pause is reachable
  // without scrolling the slideshow out of view (which would hold it).
  test("the photo, its caption and the Pause button fit one screen on load, at 720px and at 900px tall", async ({ page }) => {
    for (const height of [720, 900]) {
      await page.setViewportSize({ width: 1280, height });
      await open(page);
      const toggle = await root(page).locator(".slideshow__toggle").boundingBox();
      expect(toggle.y + toggle.height).toBeLessThanOrEqual(height);
      const stage = await root(page).locator(".slideshow__stage").boundingBox();
      expect(stage.height).toBeGreaterThanOrEqual(320); // the floor: a short window does not get a sliver
    }
  });

  test("the slideshow opens the page, above the year headings", async ({ page }) => {
    await open(page);
    const top = (await root(page).boundingBox()).y;
    const years = (await page.locator(".gallery-year").first().boundingBox()).y;
    expect(top).toBeLessThan(years);
    expect(await hasNoHorizontalScroll(page)).toBe(true);
  });
});

test.describe("The slideshow with reduced motion", () => {
  // test.use({ reducedMotion }) did not reach matchMedia here (it read false); emulateMedia does.
  test.beforeEach(async ({ page }) => { await page.emulateMedia({ reducedMotion: "reduce" }); });

  test("starts paused with Play offered, fades in 0.3 s and does not drift", async ({ page }) => {
    await open(page);
    const first = await src(page);
    await expect(root(page).locator(".slideshow__toggle")).toHaveText("Play");
    await page.mouse.move(0, 0);
    await staysFor(page, 30_000);
    expect(await activeImg(page).evaluate(i => getComputedStyle(i).animationName)).toBe("none");
    await root(page).locator(".slideshow__next").click();
    await expect.poll(() => src(page)).not.toBe(first);
    expect(await page.locator(".slideshow__layer.is-active").evaluate(l => getComputedStyle(l).transitionDuration)).toBe("0.3s");
    await root(page).locator(".slideshow__toggle").click(); // Play still works if they want it
    await page.mouse.move(0, 0);
    await idle(page);
    const now = await src(page);
    expect(await untilChange(page, now)).not.toBe(now);
  });
});

test.describe("The slideshow on a phone", () => {
  test.use({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });

  test("fits the width, keeps a 4:3 stage and 44px controls, and a tap does not hold it", async ({ page }) => {
    await open(page);
    expect(await hasNoHorizontalScroll(page)).toBe(true);
    const box = await root(page).locator(".slideshow__stage").boundingBox();
    expect(Math.abs(box.width / box.height - 4 / 3)).toBeLessThan(0.02);
    expect(box.width).toBeLessThanOrEqual(390);
    for (const sel of [".slideshow__prev", ".slideshow__toggle", ".slideshow__next"]) {
      const b = await root(page).locator(sel).boundingBox();
      expect(b.width).toBeGreaterThanOrEqual(44);
      expect(b.height).toBeGreaterThanOrEqual(44);
    }
    const first = await src(page);
    await root(page).locator(".slideshow__stage").tap({ position: { x: 5, y: 5 } }); // a touch is not a hover
    await dialog(page).locator(".figure-dialog__close").click();
    await expect(dialog(page)).toBeHidden();
    expect(await untilChange(page, first)).not.toBe(first);
  });
});
