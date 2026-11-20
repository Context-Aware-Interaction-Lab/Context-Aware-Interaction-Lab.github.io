// The Gallery's album strips (assets/js/gallery-carousel.js, the .album-carousel rules in site.css): every card the same
// size whatever its text; a year as one strip that, once it overflows, becomes a coverflow (the active card centred and
// much bigger, its neighbours smaller and faded) with arrows, a mouse drag with a flick, keyboard stepping and native
// touch swipes; and the magnified card under the mouse. Driven on the specimen at /design-language/, where 2026 holds five
// albums (enough to overflow at desktop width) and 2025 and the undated section hold one each, and on the real /gallery/.
// Card size is read from layout (offsetWidth/offsetHeight): the lens scales a card with a transform, which changes its
// painted box but not its layout box.
import { test, expect, hasNoHorizontalScroll } from "./fixtures.js";

const PAGE = "/design-language/";
const PITCH = 304; // a card (280px) plus its gap (24px)
const strip = (page, id) => page.locator(`#gallery-${id} + .album-carousel .album-cards`);
const carousel = (page, id) => page.locator(`#gallery-${id} + .album-carousel`);
const prev = (page, id) => carousel(page, id).locator(".album-carousel__prev");
const next = (page, id) => carousel(page, id).locator(".album-carousel__next");
const noArrows = (page, id) => expect(carousel(page, id).locator(".album-carousel__btn:visible")).toHaveCount(0);
const at = (page, id) => strip(page, id).evaluate(el => Math.round(el.scrollLeft));

// Layout size of every card on the page: [width, height].
const sizes = page => page.locator(".album__card").evaluateAll(els => els.map(e => [e.offsetWidth, e.offsetHeight]));

// The scale each card of a strip is painted at (1 when it has no transform), and its opacity. Both are on the .album
// wrapper, not on the clipped card, so that scaling and fading them costs no repainting.
const scales = (page, id) => strip(page, id).locator(".album").evaluateAll(els => els.map(e => {
  const t = getComputedStyle(e).transform;
  return t === "none" ? 1 : Number(t.match(/matrix\(([^,]+)/)[1]);
}));
const opacities = (page, id) => strip(page, id).locator(".album").evaluateAll(els => els.map(e => Number(getComputedStyle(e).opacity)));
const peak = list => list.indexOf(Math.max(...list));
// A transition runs 0.35s: poll until the scales stop changing.
const settled = async (page, id) => {
  let last = null;
  await expect.poll(async () => { const now = JSON.stringify(await scales(page, id)); const same = now === last; last = now; return same; }).toBe(true);
  return scales(page, id);
};
// How far the card nearest the strip's centre is from it, and which card that is.
const centred = (page, id) => strip(page, id).evaluate(el => {
  const r = el.getBoundingClientRect();
  const mid = r.left + r.width / 2;
  const d = [...el.querySelectorAll(".album")].map(a => { const b = a.getBoundingClientRect(); return Math.abs(b.left + b.width / 2 - mid); });
  const i = d.indexOf(Math.min(...d));
  return { index: i, distance: Math.round(d[i]) };
});
const settledOn = (page, id, index) => expect.poll(async () => {
  const c = await centred(page, id);
  return c.index === index && c.distance <= 2;
}).toBe(true);

// A mouse drag across a strip: press at (x, y), move by dx in `steps` moves `gap` ms apart, then pause, then release.
async function drag(page, x, y, dx, { steps = 12, gap = 16, pause = 0 } = {}) {
  await page.mouse.move(x, y);
  await page.mouse.down();
  for (let i = 1; i <= steps; i++) { await page.mouse.move(x + (dx * i) / steps, y); await page.waitForTimeout(gap); }
  if (pause) await page.waitForTimeout(pause);
  await page.mouse.up();
}
// The same drag as in-page pointer events with exact timestamps, for the tests of the throw: a real mouse's timing drifts
// with the machine's load (the strip counts a pause of over 80ms before release as "no throw"), a timestamp does not.
const syntheticDrag = (page, selector, dx, { steps, dt, hold }) => page.evaluate(({ selector, dx, steps, dt, hold }) => {
  const card = document.querySelector(selector);
  const r = card.getBoundingClientRect();
  const x0 = r.left + r.width / 2;
  const y = r.top + 100;
  let t = 1000;
  const fire = (type, x) => {
    const e = new PointerEvent(type, { pointerId: 7, pointerType: "mouse", button: 0, buttons: type === "pointerup" ? 0 : 1, clientX: x, clientY: y, bubbles: true, cancelable: true });
    Object.defineProperty(e, "timeStamp", { value: t });
    card.dispatchEvent(e);
  };
  fire("pointerdown", x0);
  for (let i = 1; i <= steps; i++) { t += dt; fire("pointermove", x0 + (dx * i) / steps); }
  t += hold;
  fire("pointerup", x0 + dx);
}, { selector, dx, steps, dt, hold });
const cardCentre = async (page, selector) => { const b = await page.locator(selector).boundingBox(); return { x: b.x + b.width / 2, y: b.y + 100 }; };

test.describe("Every album card is the same size", () => {
  test("on the specimen at desktop width, whatever the title, place or date, and the long title really is clamped", async ({ page }) => {
    await page.goto(PAGE);
    const all = await sizes(page);
    expect(all).toHaveLength(7);
    expect(new Set(all.map(s => s.join("x"))).size, `sizes: ${all.map(s => s.join("x")).join(" ")}`).toBe(1);
    expect(all[0][0]).toBe(280);
    // The test only means something if the clamp had work to do: the long title and long place overflow two lines.
    const clamped = await page.locator("#album-20261000-specimen-long .album__title").evaluate(el => el.scrollHeight > el.clientHeight + 1);
    expect(clamped).toBe(true);
    const metaClamped = await page.locator("#album-20261000-specimen-long .album__meta").evaluate(el => el.scrollHeight > el.clientHeight + 1);
    expect(metaClamped).toBe(true);
  });

  test("on a phone, at min(72vw, 280px) wide", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(PAGE);
    const all = await sizes(page);
    expect(new Set(all.map(s => s.join("x"))).size, `sizes: ${all.map(s => s.join("x")).join(" ")}`).toBe(1);
    expect(all[0][0]).toBe(280);
    await page.setViewportSize({ width: 320, height: 640 });
    const small = await sizes(page);
    expect(new Set(small.map(s => s.join("x"))).size).toBe(1);
    expect(small[0][0]).toBe(230); // 72vw of 320px is 230.4px: the card follows the screen, below the 280px cap
  });

  test("on the real page, where one title wraps to two lines and another to one", async ({ page }) => {
    await page.goto("/gallery/");
    const all = await sizes(page);
    expect(all.length).toBeGreaterThanOrEqual(3);
    expect(new Set(all.map(s => s.join("x"))).size, `sizes: ${all.map(s => s.join("x")).join(" ")}`).toBe(1);
  });
});

test.describe("A year is one strip", () => {
  test.beforeEach(async ({ page }) => { await page.goto(PAGE); });

  test("a year with more albums than fit runs on past the edge, with arrows; a year that fits has none", async ({ page }) => {
    const s = strip(page, "2026");
    expect(await s.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
    expect(await s.evaluate(el => getComputedStyle(el).overflowX)).toBe("auto");
    await expect(carousel(page, "2026")).toHaveClass(/is-overflowing/);
    await expect(prev(page, "2026")).toBeVisible();
    await expect(next(page, "2026")).toBeVisible();
    await expect(prev(page, "2026")).toHaveAttribute("aria-disabled", "true"); // at the start
    await expect(next(page, "2026")).toHaveAttribute("aria-disabled", "false");
    // 2025 and the undated section hold one card each: nothing to scroll, so no arrows.
    for (const id of ["2025", "undated"]) {
      await expect(carousel(page, id)).not.toHaveClass(/is-overflowing/);
      await noArrows(page, id);
    }
  });

  test("every card of a year sits on one row", async ({ page }) => {
    const tops = await strip(page, "2026").locator(".album__card").evaluateAll(els => els.map(e => e.offsetTop));
    expect(new Set(tops).size).toBe(1);
  });

  test("an overflowing strip opens with its first card centred; a strip that fits is a plain row from the left", async ({ page }) => {
    await settledOn(page, "2026", 0);
    const one = await strip(page, "2025").evaluate(el => {
      const r = el.getBoundingClientRect();
      const c = el.querySelector(".album__card").getBoundingClientRect();
      return Math.round(c.left - r.left);
    });
    expect(one).toBeLessThan(40); // beside the left edge (the strip's own side room), not centred
  });

  test("the strip snaps to a centred card: a scroll that stops between cards settles on the nearest", async ({ page }) => {
    const s = strip(page, "2026");
    await s.evaluate(el => el.scrollTo({ left: 200 })); // nearer the second card (304) than the first (0)
    await settledOn(page, "2026", 1);
    expect(await at(page, "2026")).toBe(PITCH);
  });

  test("tabbing to a card that is off screen brings it to the middle", async ({ page }) => {
    await page.keyboard.press("Tab"); // start keyboard modality so the focus is :focus-visible
    await page.locator("#album-20260600-specimen-conferences > summary").focus();
    await settledOn(page, "2026", 4);
  });
});

test.describe("The arrows step one card at a time", () => {
  test.use({ viewport: { width: 800, height: 700 } }); // narrow enough that 2026 needs four presses

  test("Next walks card by card to the end and dims; Previous walks back to the start and dims", async ({ page }) => {
    await page.goto(PAGE);
    const max = await strip(page, "2026").evaluate(el => Math.round(el.scrollWidth - el.clientWidth));
    expect(max).toBe(4 * PITCH); // five cards, each centred in turn
    for (const to of [1, 2, 3, 4]) {
      await next(page, "2026").click();
      await expect.poll(() => at(page, "2026")).toBe(to * PITCH);
    }
    await expect(next(page, "2026")).toHaveAttribute("aria-disabled", "true");
    await expect(prev(page, "2026")).toHaveAttribute("aria-disabled", "false");
    await next(page, "2026").click({ force: true }); // pressing a dimmed arrow does nothing
    await page.waitForTimeout(400);
    expect(await at(page, "2026")).toBe(max);
    for (const to of [3, 2, 1, 0]) {
      await prev(page, "2026").click();
      await expect.poll(() => at(page, "2026")).toBe(to * PITCH);
    }
    await expect(prev(page, "2026")).toHaveAttribute("aria-disabled", "true");
    await expect(next(page, "2026")).toHaveAttribute("aria-disabled", "false");
  });
});

test.describe("Quick presses on an arrow add up", () => {
  test.use({ viewport: { width: 800, height: 700 } });

  test("three presses in a row, without waiting, go three cards and not one", async ({ page }) => {
    await page.goto(PAGE);
    const n = next(page, "2026");
    await n.click(); await n.click(); await n.click(); // each press lands while the last smooth scroll is still running
    await expect.poll(() => at(page, "2026")).toBe(3 * PITCH);
    const p = prev(page, "2026");
    await p.click(); await p.click(); await p.click();
    await expect.poll(() => at(page, "2026")).toBe(0);
  });
});

test.describe("The coverflow", () => {
  test.beforeEach(async ({ page }) => { await page.goto(PAGE); await page.mouse.move(0, 0); });

  test("the centred card is much bigger and its neighbours shrink and fade", async ({ page }) => {
    const sc = await settled(page, "2026");
    expect(sc[0]).toBeGreaterThan(1.22); // the active card, 1.25 at its peak
    expect(sc[0]).toBeLessThanOrEqual(1.26);
    expect(Math.max(...sc.slice(1))).toBeLessThan(1); // everyone else is smaller than their natural size
    expect(Math.min(...sc)).toBeGreaterThan(0.86);
    expect(Math.min(...sc)).toBeLessThan(0.9); // down to 0.88
    const op = await opacities(page, "2026");
    expect(op[0]).toBeGreaterThan(0.98);
    expect(Math.max(...op.slice(1))).toBeLessThan(0.9); // neighbours are dimmed...
    expect(Math.min(...op)).toBeLessThan(0.6); // ...and the far ones most of all (0.55)
  });

  test("the strip has a grab cursor while it is a coverflow, and a depth shadow that is strongest on the active card", async ({ page }) => {
    expect(await strip(page, "2026").evaluate(el => getComputedStyle(el).cursor)).toBe("grab");
    expect(await strip(page, "2025").evaluate(el => getComputedStyle(el).cursor)).not.toBe("grab"); // a strip that fits is not draggable
    await settled(page, "2026");
    const shadow = await strip(page, "2026").locator(".album").evaluateAll(els => els.map(e => Number(getComputedStyle(e, "::before").opacity)));
    expect(shadow[0]).toBeGreaterThan(0.95); // the active card's shadow is fully there
    expect(Math.max(...shadow.slice(1))).toBeLessThan(0.05); // and the others have none: it follows the lens
  });

  test("scrolling the strip carries the lens along, one card at a time", async ({ page }) => {
    await page.setViewportSize({ width: 800, height: 700 });
    expect(peak(await settled(page, "2026"))).toBe(0);
    await strip(page, "2026").evaluate((el, pitch) => el.scrollTo({ left: pitch }), PITCH);
    await expect.poll(async () => peak(await settled(page, "2026"))).toBe(1);
    await strip(page, "2026").evaluate(el => el.scrollTo({ left: el.scrollWidth }));
    await expect.poll(async () => peak(await settled(page, "2026"))).toBe(4);
    const end = await settled(page, "2026");
    expect(end[4]).toBeGreaterThan(1.22);
    expect(end[0]).toBeLessThan(1); // the first card has left the lens
  });

  test("the lens is a number between 0 and 1 on each card, set by the script, and exactly one card has all of it", async ({ page }) => {
    await settled(page, "2026");
    const m = await strip(page, "2026").locator(".album").evaluateAll(els => els.map(e => Number(e.style.getPropertyValue("--m"))));
    expect(m).toHaveLength(5);
    m.forEach(x => { expect(x).toBeGreaterThanOrEqual(0); expect(x).toBeLessThanOrEqual(1); });
    expect(m[0]).toBe(1); // at rest the first card sits dead centre
    expect(m.slice(1).every(x => x < 0.01)).toBe(true); // a pitch away or more: none of it
    const single = await strip(page, "2025").locator(".album").evaluateAll(els => els.map(e => e.style.getPropertyValue("--m")));
    expect(single).toEqual(["0.000"]); // a strip that fits has no lens
  });

  test("a filter chip that leaves the strip with room clears the coverflow and the arrows, and Clear brings them back", async ({ page }) => {
    await expect(next(page, "2026")).toBeVisible();
    await page.locator('.chip[data-value="lab-life"]').click(); // 2026 keeps one lab-life album: nothing left to scroll
    await expect(page.locator("#gallery-2026 + .album-carousel .album:not([hidden])")).toHaveCount(1);
    await expect(carousel(page, "2026")).not.toHaveClass(/is-overflowing/);
    await noArrows(page, "2026");
    const only = (await settled(page, "2026")).filter((_, i) => i === 3); // the one that is still shown
    expect(only).toEqual([1]);
    expect(await strip(page, "2026").locator(".album").evaluateAll(els => els.map(e => e.style.getPropertyValue("--m")))).toEqual(["0.000", "0.000", "0.000", "0.000", "0.000"]);
    await page.locator(".gallery-filters__clear").click();
    await expect(carousel(page, "2026")).toHaveClass(/is-overflowing/);
    await expect(next(page, "2026")).toBeVisible();
    // The card that survived the filter stays where the eye was: it is the one centred and big once the others return.
    await settledOn(page, "2026", 3);
    expect(peak(await settled(page, "2026"))).toBe(3);
    expect((await settled(page, "2026"))[3]).toBeGreaterThan(1.22);
  });

  test("the page does not scroll sideways, and the biggest card is not clipped by its strip", async ({ page }) => {
    expect(await hasNoHorizontalScroll(page)).toBe(true);
    await settled(page, "2026");
    const [c, st] = await Promise.all([page.locator("#album-20261100-specimen-demos > summary").boundingBox(), strip(page, "2026").boundingBox()]);
    expect(c.y).toBeGreaterThanOrEqual(st.y); // top edge not cut off
    expect(c.y + c.height).toBeLessThanOrEqual(st.y + st.height); // nor the bottom
    expect(c.x).toBeGreaterThanOrEqual(st.x);
    expect(c.x + c.width).toBeLessThanOrEqual(st.x + st.width);
  });
});

test.describe("The magnified card under the mouse", () => {
  test.beforeEach(async ({ page }) => { await page.goto(PAGE); });

  test("a card alone on its strip grows when the mouse is over it, and settles back when it leaves", async ({ page }) => {
    const only = page.locator("#album-20250900-specimen-single > summary"); // no coverflow here, so any scale is the hover
    expect(await settled(page, "2025")).toEqual([1]);
    await only.hover();
    const hovered = await settled(page, "2025");
    expect(hovered[0]).toBeGreaterThan(1.1);
    expect(hovered[0]).toBeLessThanOrEqual(1.16); // 1.15 at its peak
    await page.mouse.move(0, 0);
    expect(await settled(page, "2025")).toEqual([1]);
  });

  test("in a coverflow the card under the mouse comes to full size and full colour, whichever card it is", async ({ page }) => {
    await page.mouse.move(0, 0);
    await settled(page, "2026");
    const third = page.locator("#album-20260912-specimen-short > summary"); // two cards from the centre: small and faded
    expect((await scales(page, "2026"))[2]).toBeLessThan(1);
    expect((await opacities(page, "2026"))[2]).toBeLessThan(0.6);
    await third.hover();
    await settled(page, "2026");
    expect((await scales(page, "2026"))[2]).toBeGreaterThan(1.22);
    await expect.poll(async () => (await opacities(page, "2026"))[2]).toBeGreaterThan(0.98);
  });

  test("a card with keyboard focus is magnified too", async ({ page }) => {
    await page.keyboard.press("Tab"); // start keyboard modality so focus is :focus-visible
    await page.locator("#album-specimen-undated > summary").focus();
    expect((await settled(page, "undated"))[0]).toBeGreaterThan(1.1);
  });
});

// Drags start on the centred first card: at desktop width the third sits under the right-hand arrow, which would take the press.
// What made it jerky, held in place. Each of these is a cause rather than a symptom: a symptom (frames per second) depends on
// the machine, a cause does not.
test.describe("How the lens is drawn", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(PAGE);
    await strip(page, "2026").evaluate(el => el.scrollIntoView({ block: "center", behavior: "instant" }));
    await page.mouse.move(0, 0);
    await settledOn(page, "2026", 0);
  });

  test("scale and fade are not transitioned, so the lens cannot trail the scroll; only the hover lift is eased", async ({ page }) => {
    const album = page.locator("#album-20261100-specimen-demos");
    expect(await album.evaluate(el => getComputedStyle(el).transitionProperty)).toBe("--h"); // not transform, not opacity
    expect(await album.locator("> summary").evaluate(el => getComputedStyle(el).transitionProperty)).toBe("border-color");
  });

  test("the shadow is a pseudo-element whose opacity changes, and the clipped card itself carries no transform, opacity or shadow", async ({ page }) => {
    const card = page.locator("#album-20261100-specimen-demos > summary");
    expect(await card.evaluate(el => { const c = getComputedStyle(el); return [c.transform, c.opacity, c.boxShadow].join("|"); })).toBe("none|1|none");
    expect(await page.locator("#album-20261100-specimen-demos").evaluate(el => getComputedStyle(el, "::before").boxShadow)).not.toBe("none");
  });

  test("the lens settles with the scroll: it stops within a couple of frames of the strip stopping, never after", async ({ page }) => {
    const r = await page.evaluate(async () => {
      const el = document.querySelector("#gallery-2026 + .album-carousel .album-cards");
      const albums = [...el.querySelectorAll(".album")];
      const frame = () => new Promise(res => requestAnimationFrame(res));
      const scale = a => { const t = getComputedStyle(a).transform; return t === "none" ? 1 : +t.match(/matrix\(([^,]+)/)[1]; };
      let lastX = el.scrollLeft, lastS = albums.map(scale), lastMove = 0, lastChange = 0;
      document.querySelector("#gallery-2026 + .album-carousel .album-carousel__next").click();
      for (let f = 1; f <= 120; f++) {
        await frame();
        const x = el.scrollLeft, s = albums.map(scale);
        if (Math.abs(x - lastX) > 0.01) lastMove = f;
        if (s.some((v, i) => Math.abs(v - lastS[i]) > 0.002)) lastChange = f;
        lastX = x; lastS = s;
      }
      return { lastMove, lastChange };
    });
    expect(r.lastMove).toBeGreaterThan(5); // it did scroll
    expect(r.lastChange).toBeLessThanOrEqual(r.lastMove + 2); // with a 0.35s transition on the scale this was ~20 frames after
  });

  test("the cards are promoted to their own layers only while the strip moves, and released at rest", async ({ page }) => {
    const album = page.locator("#album-20261100-specimen-demos");
    expect(await album.evaluate(el => getComputedStyle(el).willChange)).toBe("auto"); // at rest: drawn crisp, no layer
    await next(page, "2026").click();
    await expect(carousel(page, "2026")).toHaveClass(/is-moving/);
    expect(await album.evaluate(el => getComputedStyle(el).willChange)).toBe("transform, opacity"); // while moving: a compositor layer
    await expect(carousel(page, "2026")).not.toHaveClass(/is-moving/); // and released a moment after it stops
    expect(await album.evaluate(el => getComputedStyle(el).willChange)).toBe("auto");
  });

  test("after a drag is released, snapping stays off until the strip has arrived: it never snap-jumps part-way", async ({ page }) => {
    // In-page pointer events with exact timestamps (a real mouse's timing drifts and can cancel the throw), then a sample of
    // the strip's position and state on every frame from the moment of release.
    const samples = await page.evaluate(async () => {
      const el = document.querySelector("#gallery-2026 + .album-carousel .album-cards");
      const card = document.querySelector("#album-20261100-specimen-demos");
      const r = card.getBoundingClientRect();
      const x0 = r.left + r.width / 2, y = r.top + 100;
      let t = 1000;
      const fire = (type, x) => {
        const e = new PointerEvent(type, { pointerId: 9, pointerType: "mouse", button: 0, buttons: type === "pointerup" ? 0 : 1, clientX: x, clientY: y, bubbles: true, cancelable: true });
        Object.defineProperty(e, "timeStamp", { value: t });
        card.dispatchEvent(e);
      };
      fire("pointerdown", x0);
      for (let i = 1; i <= 6; i++) { t += 8; fire("pointermove", x0 - (300 * i) / 6); }
      await new Promise(res => requestAnimationFrame(res)); // let the held position be drawn
      t += 4;
      fire("pointerup", x0 - 300); // thrown: it carries on to a card about one card further
      const out = [];
      const t0 = performance.now();
      while (performance.now() - t0 < 1800) {
        await new Promise(res => requestAnimationFrame(res));
        out.push({ x: el.scrollLeft, dragging: el.classList.contains("is-dragging") });
      }
      return out;
    });
    const final = samples.at(-1).x;
    expect(Math.abs(final - 300)).toBeGreaterThan(100); // it travelled a good way after the release, from about 300 to a card centre
    expect(samples.filter(s => !s.dragging && Math.abs(s.x - final) > 4)).toHaveLength(0); // snapping was never on while still on the way
    expect(samples.at(-1).dragging).toBe(false); // and it is on again once there
  });
});

test.describe("Dragging with a mouse", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(PAGE);
    // boundingBox() is in viewport coordinates, so the strips must be on screen before a mouse is aimed at them.
    await strip(page, "2026").evaluate(el => el.scrollIntoView({ block: "center", behavior: "instant" }));
    await page.mouse.move(0, 0);
    await settledOn(page, "2026", 0);
  });

  test("the strip follows the pointer, then settles with a card centred, and the drag opens nothing", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20261100-specimen-demos");
    await drag(page, x, y, -420, { steps: 14, gap: 16, pause: 160 }); // pulled left 420px, held, let go: no throw
    await settledOn(page, "2026", 1); // 420 is 1.4 cards; with no throw it settles on the nearest, card 1
    expect(Math.abs(await at(page, "2026") - PITCH)).toBeLessThanOrEqual(2); // the target comes from fractional positions: allow a pixel of rounding
    await page.mouse.move(0, 0);
    await expect(page.locator("#figure-dialog")).toBeHidden(); // letting go over a card did not open it
    expect(await page.locator("details.album[open]").count()).toBe(0);
    await expect(strip(page, "2026")).not.toHaveClass(/is-dragging/);
    expect(peak(await settled(page, "2026"))).toBe(1); // and the lens went with it
  });

  test("the strip really follows the pointer while it is held", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20261100-specimen-demos");
    await page.mouse.move(x, y);
    await page.mouse.down();
    for (let i = 1; i <= 8; i++) { await page.mouse.move(x - i * 25, y); await page.waitForTimeout(16); }
    await expect(strip(page, "2026")).toHaveClass(/is-dragging/);
    expect(await at(page, "2026")).toBeGreaterThan(150); // 200px dragged, 6px of it before it counted as a drag
    expect(await at(page, "2026")).toBeLessThanOrEqual(200);
    expect(await strip(page, "2026").evaluate(el => getComputedStyle(el).scrollSnapType)).toBe("none"); // snapping off, so it can follow
    await page.mouse.up();
    // Where it settles depends on whether the release came inside the throw window (card 1 or card 2): either is fine here.
    await expect.poll(async () => { const c = await centred(page, "2026"); return c.distance <= 2 && c.index >= 1; }).toBe(true);
  });

  test("a quick short flick carries on to the next card; a slow drag of the same length falls back", async ({ page }) => {
    await syntheticDrag(page, "#album-20261100-specimen-demos", -140, { steps: 5, dt: 10, hold: 5 }); // 140px (under half a card), thrown at 2.8px/ms
    await settledOn(page, "2026", 1);
    await expect(strip(page, "2026")).not.toHaveClass(/is-dragging/); // the glide has finished
    await page.mouse.move(0, 0);
    await strip(page, "2026").evaluate(el => el.scrollTo({ left: 0 }));
    await settledOn(page, "2026", 0);
    await syntheticDrag(page, "#album-20261100-specimen-demos", -140, { steps: 14, dt: 20, hold: 200 }); // the same distance, slowly, held 200ms before letting go
    await settledOn(page, "2026", 0);
    expect(await at(page, "2026")).toBeLessThanOrEqual(1); // back at the start, give or take a pixel of rounding
  });

  test("a throw needs the pointer still moving at release: a pause of a tenth of a second or more cancels it", async ({ page }) => {
    await syntheticDrag(page, "#album-20261100-specimen-demos", -140, { steps: 5, dt: 10, hold: 79 }); // fast, then 79ms: still a throw
    await settledOn(page, "2026", 1);
    await expect(strip(page, "2026")).not.toHaveClass(/is-dragging/); // the glide has finished
    await strip(page, "2026").evaluate(el => el.scrollTo({ left: 0 }));
    await settledOn(page, "2026", 0);
    await syntheticDrag(page, "#album-20261100-specimen-demos", -140, { steps: 5, dt: 10, hold: 90 }); // fast, then 90ms: it has stopped
    await settledOn(page, "2026", 0);
  });

  test("a hard flick is capped: it goes on one card, not five", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20261100-specimen-demos");
    await drag(page, x, y, -300, { steps: 3, gap: 4 }); // very fast
    await expect.poll(async () => (await centred(page, "2026")).distance).toBeLessThanOrEqual(2);
    expect(await at(page, "2026")).toBeLessThanOrEqual(2 * PITCH); // at most a couple of cards, never the whole strip
  });

  test("a plain click, without moving, still opens the card it is on", async ({ page }) => {
    await page.locator("#album-20261000-specimen-long > summary").click(); // not centred: the click must reach it anyway
    await expect(page.locator("#figure-dialog")).toBeVisible();
    await expect(page.locator(".figure-dialog__title")).toContainText("very long title");
  });

  test("a press that moves only a few pixels is still a click, not a drag", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20261100-specimen-demos");
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x + 3, y);
    await page.mouse.up();
    await expect(page.locator("#figure-dialog")).toBeVisible();
  });

  test("a strip that fits is not draggable: nothing moves and nothing is left in a dragging state", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20250900-specimen-single");
    await page.mouse.move(x, y);
    await page.mouse.down();
    for (let i = 1; i <= 6; i++) { await page.mouse.move(x - i * 30, y); await page.waitForTimeout(16); }
    await expect(strip(page, "2025")).not.toHaveClass(/is-dragging/);
    await page.mouse.up();
    expect(await at(page, "2025")).toBe(0);
  });

  test("text is not selected and the cover image is not dragged away while dragging", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20261100-specimen-demos");
    await drag(page, x, y, -300, { steps: 10, gap: 16, pause: 120 });
    expect(await page.evaluate(() => String(getSelection()))).toBe("");
    await settledOn(page, "2026", 1);
  });
});

// What made a mouse drag feel jerky, held in place: hover fighting the lens, a jump when the drag begins, and a stop-and-restart at
// the moment of letting go. Each is checked as a cause, not as a frame rate.
test.describe("A mouse drag feels continuous", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(PAGE);
    await strip(page, "2026").evaluate(el => el.scrollIntoView({ block: "center", behavior: "instant" }));
    await page.mouse.move(0, 0);
    await settledOn(page, "2026", 0);
  });

  test("hover is switched off while dragging: only the lens makes a card big, however many pass under the pointer", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20261100-specimen-demos");
    await page.mouse.move(x, y);
    await page.mouse.down();
    let most = 0;
    for (let i = 1; i <= 20; i++) {
      await page.mouse.move(x - i * 18, y);
      await page.waitForTimeout(24);
      const big = (await scales(page, "2026")).filter(v => v > 1.15).length;
      most = Math.max(most, big);
    }
    expect(await strip(page, "2026").locator(".album").first().evaluate(el => getComputedStyle(el).pointerEvents)).toBe("none");
    expect(most).toBeLessThanOrEqual(1); // before: the card held under the pointer stayed big while the lens made another one big too
    await page.mouse.up();
    await expect(strip(page, "2026")).not.toHaveClass(/is-dragging/);
  });

  test("after letting go the card under a resting pointer does not pop up; moving the mouse brings hover back", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20261100-specimen-demos");
    await drag(page, x, y, -300, { steps: 12, gap: 16, pause: 120 }); // settles on card 1; the pointer ends over card 0, now small and faded
    await settledOn(page, "2026", 1);
    await expect(strip(page, "2026")).not.toHaveClass(/is-dragging/);
    await expect(strip(page, "2026")).toHaveClass(/after-drag/);
    const rested = await settled(page, "2026");
    expect(rested.filter(v => v > 1.15)).toHaveLength(1); // only the lens card
    expect(rested[0]).toBeLessThan(1); // not the card the pointer happens to be over
    await page.mouse.move(x - 300 + 12, y + 4); // the mouse moves: hover is back
    await expect(strip(page, "2026")).not.toHaveClass(/after-drag/);
    await page.mouse.move(x - 300 + 18, y + 7); // a real mouse keeps sending events: the next one finds the card under it
    await expect.poll(async () => (await scales(page, "2026"))[0]).toBeGreaterThan(1.2);
  });

  test("the drag begins where the pointer is: the few pixels of dead zone are not applied as a jump", async ({ page }) => {
    const { x, y } = await cardCentre(page, "#album-20261100-specimen-demos");
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.mouse.move(x - 3, y);
    await page.mouse.move(x - 7, y); // 7px: past the 6px threshold, so the drag begins here
    await page.waitForTimeout(80);
    await expect(strip(page, "2026")).toHaveClass(/is-dragging/);
    expect(await at(page, "2026")).toBeLessThanOrEqual(1); // before: it jumped by the whole 7px at once
    await page.mouse.move(x - 27, y); // 20px further
    await page.waitForTimeout(80);
    const moved = await at(page, "2026");
    expect(moved).toBeGreaterThanOrEqual(18);
    expect(moved).toBeLessThanOrEqual(22); // it follows the pointer from where the drag began
    await page.mouse.up();
  });

  test("letting go carries the speed on: the glide starts fast, at the pointer's speed, it does not stop and re-accelerate", async ({ page }) => {
    // A throw with exact timestamps (about 4.6px/ms by the end), then the strip's speed over the first frames after release.
    // A smooth scroll started from a standstill managed about 0.2px/ms over the same frames; the spring starts at the throw.
    const speed = await page.evaluate(async () => {
      const el = document.querySelector("#gallery-2026 + .album-carousel .album-cards");
      const card = document.querySelector("#album-20261100-specimen-demos");
      const r = card.getBoundingClientRect(), x0 = r.left + r.width / 2, y = r.top + 100;
      let t = 1000;
      const fire = (type, x) => {
        const e = new PointerEvent(type, { pointerId: 11, pointerType: "mouse", button: 0, buttons: type === "pointerup" ? 0 : 1, clientX: x, clientY: y, bubbles: true, cancelable: true });
        Object.defineProperty(e, "timeStamp", { value: t });
        card.dispatchEvent(e);
      };
      fire("pointerdown", x0);
      for (let i = 1; i <= 6; i++) { t += 8; fire("pointermove", x0 - (250 * i) / 6); }
      await new Promise(res => requestAnimationFrame(res)); // the held position is drawn
      t += 4;
      const frames = [];
      fire("pointerup", x0 - 250);
      frames.push({ t: performance.now(), x: el.scrollLeft });
      for (let i = 0; i < 4; i++) { await new Promise(res => requestAnimationFrame(res)); frames.push({ t: performance.now(), x: el.scrollLeft }); }
      const first = frames[0], last = frames[frames.length - 1];
      return { perMs: (last.x - first.x) / (last.t - first.t), frames: frames.length, moved: last.x - first.x };
    });
    expect(speed.moved).toBeGreaterThan(20); // it is moving
    expect(speed.perMs).toBeGreaterThan(1.2); // and fast from the first frame
  });

  test("a press on a gliding strip takes hold of it, and letting go without dragging settles it on the nearest card", async ({ page }) => {
    await syntheticDrag(page, "#album-20261100-specimen-demos", -250, { steps: 6, dt: 8, hold: 4 }); // thrown: it glides on
    await page.waitForTimeout(60); // part-way through the glide
    await page.evaluate(() => {
      const el = document.querySelector("#gallery-2026 + .album-carousel .album-cards");
      const fire = type => { const e = new PointerEvent(type, { pointerId: 8, pointerType: "mouse", button: 0, buttons: type === "pointerup" ? 0 : 1, clientX: 400, clientY: 400, bubbles: true, cancelable: true }); el.dispatchEvent(e); };
      fire("pointerdown"); fire("pointerup"); // grabbed and let go, no movement
    });
    await settledOn(page, "2026", (await centred(page, "2026")).index); // it settles on a card, wherever it was
    await expect.poll(async () => (await centred(page, "2026")).distance).toBeLessThanOrEqual(2);
    await expect(strip(page, "2026")).not.toHaveClass(/is-dragging/); // not left stuck in a dragging state
  });

  test("the wheel, a touch and an arrow take over a glide at once, instead of being overwritten by it", async ({ page }) => {
    // Read straight after the event: left alone, a glide clears this state by itself within about 400ms, so waiting for it to
    // clear would pass either way. What matters is that it has let go by the time the input has been handled.
    for (const how of ["wheel", "touchstart"]) {
      await strip(page, "2026").evaluate(el => el.scrollTo({ left: 0 }));
      await settledOn(page, "2026", 0);
      await syntheticDrag(page, "#album-20261100-specimen-demos", -250, { steps: 6, dt: 8, hold: 4 });
      await page.waitForTimeout(40);
      const still = await strip(page, "2026").evaluate(el => el.classList.contains("is-dragging"));
      expect(still, "the glide should still be running before the input").toBe(true);
      const after = await strip(page, "2026").evaluate((el, kind) => {
        el.dispatchEvent(kind === "wheel" ? new WheelEvent("wheel", { deltaX: 3, bubbles: true }) : new Event("touchstart", { bubbles: true }));
        return el.classList.contains("is-dragging");
      }, how);
      expect(after, `${how} should take the strip back from the glide`).toBe(false);
      await expect.poll(async () => (await centred(page, "2026")).distance).toBeLessThanOrEqual(2); // native snapping settles it
    }
    await strip(page, "2026").evaluate(el => el.scrollTo({ left: 0 }));
    await settledOn(page, "2026", 0);
    await syntheticDrag(page, "#album-20261100-specimen-demos", -250, { steps: 6, dt: 8, hold: 4 });
    await page.waitForTimeout(40);
    await next(page, "2026").click();
    expect(await strip(page, "2026").evaluate(el => el.classList.contains("is-dragging"))).toBe(false); // an arrow takes it back too
  });
});

test.describe("Keyboard", () => {
  test.beforeEach(async ({ page }) => { await page.goto(PAGE); await page.keyboard.press("Tab"); });

  test("the left and right arrow keys move focus from card to card and bring each to the middle", async ({ page }) => {
    await page.locator("#album-20261100-specimen-demos > summary").focus();
    await settledOn(page, "2026", 0);
    await page.keyboard.press("ArrowRight");
    await expect(page.locator("#album-20261000-specimen-long > summary")).toBeFocused();
    await settledOn(page, "2026", 1);
    await page.keyboard.press("ArrowRight");
    await expect(page.locator("#album-20260912-specimen-short > summary")).toBeFocused();
    await settledOn(page, "2026", 2);
    await page.keyboard.press("ArrowLeft");
    await expect(page.locator("#album-20261000-specimen-long > summary")).toBeFocused();
    await settledOn(page, "2026", 1);
  });

  test("the arrow keys stop at either end of the strip", async ({ page }) => {
    const first = page.locator("#album-20261100-specimen-demos > summary");
    await first.focus();
    await page.keyboard.press("ArrowLeft");
    await expect(first).toBeFocused();
    const last = page.locator("#album-20260600-specimen-conferences > summary");
    await last.focus();
    await page.keyboard.press("ArrowRight");
    await expect(last).toBeFocused();
  });
});

test.describe("Swiping on a touch screen", () => {
  test.use({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });

  test("a swipe moves the strip, one card at a time, and the card it lands on is the big one", async ({ page }) => {
    await page.goto(PAGE);
    const s = strip(page, "2026");
    const y = await s.evaluate(el => {
      el.scrollIntoView({ block: "center", behavior: "instant" });
      const box = el.getBoundingClientRect();
      return box.top + box.height / 2;
    });
    await settledOn(page, "2026", 0);
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Input.synthesizeScrollGesture", { x: 300, y, xDistance: -350, yDistance: 0, speed: 1200, gestureSourceType: "touch" });
    await expect.poll(async () => (await at(page, "2026")) > 0).toBe(true);
    await expect.poll(async () => (await centred(page, "2026")).distance).toBeLessThanOrEqual(2); // settled on a card
    const landed = (await centred(page, "2026")).index;
    expect(landed).toBeGreaterThan(0);
    expect(landed).toBeLessThanOrEqual(1); // snap-stop: one swipe is one card, however hard it was thrown
    expect(peak(await settled(page, "2026"))).toBe(landed);
  });
});

test.describe("The coverflow with reduced motion", () => {
  test("nothing scales or fades: no lens and no hover zoom, but the hover still marks the card", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(PAGE);
    await page.mouse.move(0, 0);
    expect((await settled(page, "2026")).every(x => x === 1)).toBe(true);
    expect((await opacities(page, "2026")).every(x => x === 1)).toBe(true);
    const card = page.locator("#album-20261100-specimen-demos > summary");
    await card.hover();
    expect((await settled(page, "2026")).every(x => x === 1)).toBe(true);
    expect(await card.evaluate(el => getComputedStyle(el).borderTopColor)).not.toBe(await page.locator("#album-20260800-specimen-no-place > summary").evaluate(el => getComputedStyle(el).borderTopColor));
  });

  test("an arrow moves the strip instantly rather than smoothly", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto(PAGE);
    await next(page, "2026").click();
    await expect.poll(() => at(page, "2026")).toBeGreaterThan(0);
  });

  test("on a phone too: the overflow rule that gives it its own scale does not win over reduced motion", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(PAGE);
    expect((await settled(page, "2026")).every(x => x === 1)).toBe(true);
  });
});
