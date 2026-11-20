// The pure part of assets/js/gallery-filter.js, the Gallery page's category chips: reading ?category= and deciding
// which albums stay. The chips, the hidden albums and the address bar need a real page and an album to filter, which
// the site does not have until the first album exists (see "Done-gate exemptions" in AGENTS.md). Run:
// bun test tests/gallery-filter.test.js
import { expect, test } from "bun:test";
import { createRequire } from "node:module";

const { parse, visible } = createRequire(import.meta.url)("../assets/js/gallery-filter.js");
const known = ["conferences", "lab-life", "outreach", "demos"];

test("no category in the address means no filter", () => {
  expect(parse("", known)).toEqual([]);
  expect(parse("?q=x", known)).toEqual([]);
  expect(parse("?category=", known)).toEqual([]);
});

test("a comma list is read in order, wherever it sits in the query", () => {
  expect(parse("?category=lab-life,demos", known)).toEqual(["lab-life", "demos"]);
  expect(parse("?x=1&category=outreach", known)).toEqual(["outreach"]);
});

test("unknown ids and repeats are dropped, so a stale or hand-edited link cannot hide every album", () => {
  expect(parse("?category=nope", known)).toEqual([]);
  expect(parse("?category=demos,demos,nope,,lab-life", known)).toEqual(["demos", "lab-life"]);
});

test("encoded ids are decoded", () => {
  expect(parse("?category=lab%2Dlife", known)).toEqual(["lab-life"]);
});

test("nothing selected shows every album", () => {
  expect(visible(["demos", "outreach", "demos"], [])).toEqual([true, true, true]);
});

test("selected categories add up: an album stays when its category is any of them", () => {
  const albums = ["conferences", "demos", "outreach", "demos", "lab-life"];
  expect(visible(albums, ["demos"])).toEqual([false, true, false, true, false]);
  expect(visible(albums, ["demos", "lab-life"])).toEqual([false, true, false, true, true]);
});

test("no albums gives no answers", () => {
  expect(visible([], ["demos"])).toEqual([]);
});
