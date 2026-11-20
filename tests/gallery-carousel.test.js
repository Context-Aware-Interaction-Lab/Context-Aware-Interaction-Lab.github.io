// The pure part of assets/js/gallery-carousel.js, the album strip on /gallery/: how much a card is magnified by how far
// it is from the strip's centre, how far an arrow scrolls, and when the strip overflows or sits at an end. The
// scrolling, the arrows and the observers need a real page and are covered by e2e/carousel.spec.js. Run:
// bun test tests/gallery-carousel.test.js
import { expect, test } from "bun:test";
import { createRequire } from "node:module";

const { magnification, step, edges } = createRequire(import.meta.url)("../assets/js/gallery-carousel.js");

test("a card at the centre is fully magnified and one a span away is not at all", () => {
  expect(magnification(0, 300)).toBe(1);
  expect(magnification(300, 300)).toBeCloseTo(0, 10);
  expect(magnification(-300, 300)).toBeCloseTo(0, 10);
});

test("it falls off the same way left and right of the centre", () => {
  for (const d of [10, 75, 150, 299]) expect(magnification(d, 300)).toBeCloseTo(magnification(-d, 300), 12);
});

test("it only ever decreases as a card moves away from the centre", () => {
  let last = Infinity;
  for (let d = 0; d <= 300; d += 5) {
    const m = magnification(d, 300);
    expect(m).toBeLessThanOrEqual(last);
    last = m;
  }
});

test("beyond the span it stays at zero, never negative, and stays within 0 and 1 everywhere", () => {
  expect(magnification(301, 300)).toBe(0);
  expect(magnification(5000, 300)).toBe(0);
  for (let d = -900; d <= 900; d += 7) {
    const m = magnification(d, 300);
    expect(m).toBeGreaterThanOrEqual(0);
    expect(m).toBeLessThanOrEqual(1);
  }
});

test("a zero or missing span magnifies nothing instead of dividing by zero", () => {
  expect(magnification(0, 0)).toBe(0);
  expect(magnification(10, 0)).toBe(0);
  expect(magnification(10, undefined)).toBe(0);
  expect(Number.isNaN(magnification(0, 0))).toBe(false);
});

test("an arrow scrolls one card plus its gap, forward or back", () => {
  expect(step(280, 24, 1)).toBe(304);
  expect(step(280, 24, -1)).toBe(-304);
  expect(step(280.5, 24, 1)).toBeCloseTo(304.5, 10);
});

test("a strip that fits does not overflow and counts as at both ends", () => {
  expect(edges(0, 1200, 1200)).toEqual({ overflows: false, atStart: true, atEnd: true });
  expect(edges(0, 1200, 1200.8)).toEqual({ overflows: false, atStart: true, atEnd: true }); // sub-pixel rounding
});

test("a strip that overflows is at the start, in the middle, then at the end", () => {
  expect(edges(0, 1200, 1800)).toEqual({ overflows: true, atStart: true, atEnd: false });
  expect(edges(300, 1200, 1800)).toEqual({ overflows: true, atStart: false, atEnd: false });
  expect(edges(600, 1200, 1800)).toEqual({ overflows: true, atStart: false, atEnd: true });
});

test("a fraction of a pixel short of an end still counts as the end, so the arrow dims", () => {
  expect(edges(599.4, 1200, 1800).atEnd).toBe(true);
  expect(edges(0.6, 1200, 1800).atStart).toBe(true);
  expect(edges(2, 1200, 1800).atStart).toBe(false);
});

// ---- overflows: do the cards fit? Decided from the cards' own width, never from scrollWidth, because the centring padding
// a strip gets once it overflows would otherwise make every strip look as if it overflowed.
const { overflows, snapTarget } = createRequire(import.meta.url)("../assets/js/gallery-carousel.js");

test("cards that fit the width do not overflow, and one pixel over does", () => {
  expect(overflows(4, 280, 24, 1192)).toBe(false); // 4 x 280 + 3 x 24 = 1192 exactly
  expect(overflows(4, 280, 24, 1200)).toBe(false);
  expect(overflows(5, 280, 24, 1200)).toBe(true); // 1496
  expect(overflows(4, 280, 24, 1190)).toBe(true);
});

test("a single card never overflows, and nothing overflows when there are no cards", () => {
  expect(overflows(1, 280, 24, 1200)).toBe(false);
  expect(overflows(0, 280, 24, 1200)).toBe(false);
});

test("on a phone two cards overflow and one does not", () => {
  expect(overflows(2, 280, 12, 358)).toBe(true); // 572 in 358
  expect(overflows(1, 280, 12, 358)).toBe(false);
});

test("the edge is exact to within one pixel of slack, as for edges(): 888 needed, 887 still counts as fitting, 886 overflows", () => {
  expect(overflows(3, 280, 24, 888)).toBe(false); // 3 x 280 + 2 x 24 = 888
  expect(overflows(3, 280, 24, 887)).toBe(false); // sub-pixel rounding is not an overflow
  expect(overflows(3, 280, 24, 886)).toBe(true);
});

// ---- snapTarget: where a strip settles after a drag, from the card centres, how fast it was thrown and how far a throw may go.
const centres = [140, 444, 748, 1052, 1356]; // cards 280 wide, 24 apart: a pitch of 304

test("a drag that stops over a card settles on that card, centred", () => {
  // strip 600 wide, scrolled so its centre is at 450: card 2 (444) is nearest, so the strip centres on it
  expect(snapTarget(150, 600, centres, 0, 200, 456)).toBe(144);
  expect(snapTarget(150, 600, centres, 0, 200, 456) + 300).toBe(444);
});

test("a flick forward carries it on to the next card and a flick back to the previous one", () => {
  const forward = snapTarget(150, 600, centres, 0.9, 200, 456); // here 450, thrown right at 0.9 px/ms: projects to 630
  expect(forward + 300).toBe(748);
  const back = snapTarget(450, 600, centres, -0.9, 200, 456); // here 750, thrown left: projects to 570
  expect(back + 300).toBe(444);
});

test("a slow drag does not skip a card; a gentle push stays on the nearest one", () => {
  expect(snapTarget(150, 600, centres, 0.1, 200, 456) + 300).toBe(444);
  expect(snapTarget(150, 600, centres, -0.1, 200, 456) + 300).toBe(444);
});

test("a very hard flick is capped so it cannot fling past many cards", () => {
  // from a centre of 450 a limit of 420 allows a projection of at most 870, which is nearest the card at 748
  expect(snapTarget(150, 600, centres, 50, 200, 420) + 300).toBe(748);
  // and going back: from a centre of 750 a limit of 420 reaches no further than 330, which is nearest the card at 444
  expect(snapTarget(450, 600, centres, -50, 200, 420) + 300).toBe(444);
});

test("it never asks for a negative scroll position, and does nothing when there are no cards", () => {
  expect(snapTarget(0, 600, [100], 0, 200, 456)).toBe(0); // the card centre 100 would need -200
  expect(snapTarget(37, 600, [], 0.9, 200, 456)).toBe(37);
});
