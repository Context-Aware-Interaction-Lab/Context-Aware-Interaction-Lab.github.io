// The pure part of assets/js/gallery-slideshow.js, the Gallery's opening slideshow: the order photos are shown in.
// The timer, the crossfade and the pause rules need a real page and are covered by e2e/gallery.spec.js. Run:
// bun test tests/gallery-slideshow.test.js
import { expect, test } from "bun:test";
import { createRequire } from "node:module";

const { order } = createRequire(import.meta.url)("../assets/js/gallery-slideshow.js");

// A small seeded generator (mulberry32), so a shuffle is repeatable in a test.
function seeded(seed) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

test("the order holds every index exactly once", () => {
  for (const n of [2, 3, 10, 32]) {
    const o = order(n, seeded(n));
    expect(o).toHaveLength(n);
    expect([...o].sort((x, y) => x - y)).toEqual([...Array(n).keys()]);
  }
});

test("the same random source gives the same order, a different one a different order", () => {
  expect(order(32, seeded(7))).toEqual(order(32, seeded(7)));
  expect(order(32, seeded(7))).not.toEqual(order(32, seeded(8)));
});

test("the order is actually shuffled, not the identity", () => {
  expect(order(32, seeded(1))).not.toEqual([...Array(32).keys()]);
});

test("a new cycle never opens on the photo that ended the last one", () => {
  for (let seed = 0; seed < 200; seed++) {
    for (const last of [0, 1, 4]) {
      expect(order(5, seeded(seed), last)[0]).not.toBe(last);
    }
  }
});

test("avoiding the first photo still gives a full permutation", () => {
  const o = order(6, seeded(3), 2);
  expect([...o].sort((x, y) => x - y)).toEqual([0, 1, 2, 3, 4, 5]);
});

test("no photos gives an empty order; one photo gives that photo even when it is the one to avoid", () => {
  expect(order(0, seeded(1))).toEqual([]);
  expect(order(1, seeded(1))).toEqual([0]);
  expect(order(1, seeded(1), 0)).toEqual([0]);
});

test("an avoid value outside the pool changes nothing", () => {
  expect(order(5, seeded(9), -1)).toEqual(order(5, seeded(9)));
  expect(order(5, seeded(9), 99)).toEqual(order(5, seeded(9)));
});
