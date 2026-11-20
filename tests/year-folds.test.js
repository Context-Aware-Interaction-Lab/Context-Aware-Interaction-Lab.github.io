// Behaviour of assets/js/year-folds.js, the Publications page's year folds. Run: bun test tests/year-folds.test.js
// The script is a classic script, so it is evaluated against a minimal stand-in for `document` and `window`
// (the DOM is the boundary; the layout and real deep links are checked in a real browser).
import { beforeEach, expect, test } from "bun:test";
import { readFileSync } from "node:fs";

const SOURCE = readFileSync(new URL("../assets/js/year-folds.js", import.meta.url), "utf8");

let page, win;

const node = (tag, id, parent, open = false) => {
  const handlers = {};
  const n = {
    tagName: tag.toUpperCase(),
    id,
    parentElement: parent,
    open,
    scrolled: 0,
    hidden: true,
    textContent: "Expand all",
    children: [],
    handlers,
    scrollIntoView() { this.scrolled += 1; },
    addEventListener(type, fn) { (handlers[type] ||= []).push(fn); },
    fire(type, event = {}) { (handlers[type] || []).forEach(fn => fn(event)); },
    // Enough of querySelector for the one selector the script uses on a section.
    querySelector(selector) {
      return selector === "details.year" ? this.children.find(c => c.tagName === "DETAILS") || null : null;
    },
  };
  if (parent) parent.children.push(n);
  return n;
};

// <section id=Y><details class="year"><ul><li id="pub-Y-a"></li></ul></details></section>, newest year open.
const buildYear = (year, open) => {
  const section = node("section", String(year), null);
  const details = node("details", undefined, section, open);
  const list = node("ul", undefined, details);
  const row = node("li", `pub-${year}-a`, list);
  return { section, details, row };
};

const load = (hash = "") => {
  const years = { 2026: buildYear(2026, true), 2025: buildYear(2025, false), 2024: buildYear(2024, false) };
  const button = node("button", undefined, null);
  const byId = {};
  Object.values(years).forEach(y => { byId[y.section.id] = y.section; byId[y.row.id] = y.row; });
  const winHandlers = {};
  win = {
    location: { hash },
    addEventListener(type, fn) { (winHandlers[type] ||= []).push(fn); },
    fire(type) { (winHandlers[type] || []).forEach(fn => fn()); },
  };
  const document = {
    querySelectorAll: selector => (selector === "details.year" ? Object.values(years).map(y => y.details) : []),
    querySelector: selector => (selector === ".year-controls__all" ? button : null),
    getElementById: id => byId[id] || null,
  };
  new Function("document", "window", SOURCE)(document, win);
  page = { years, button };
};

const openYears = () => Object.entries(page.years).filter(([, y]) => y.details.open).map(([year]) => year).sort();

beforeEach(() => load());

test("with no hash, nothing opens or scrolls and the Expand all button is revealed", () => {
  expect(openYears()).toEqual(["2026"]);
  expect(page.button.hidden).toBe(false);
  expect(page.button.textContent).toBe("Expand all");
  Object.values(page.years).forEach(y => expect(y.row.scrolled + y.section.scrolled).toBe(0));
});

test("a link to a paper in a closed year opens that year and scrolls to the paper", () => {
  load("#pub-2024-a");
  expect(openYears()).toEqual(["2024", "2026"]);
  expect(page.years[2024].row.scrolled).toBe(1);
});

test("a link to a year opens that year and scrolls to it", () => {
  load("#2025");
  expect(openYears()).toEqual(["2025", "2026"]);
  expect(page.years[2025].section.scrolled).toBe(1);
});

test("a link to a paper in the year that is already open changes nothing and does not re-scroll", () => {
  load("#pub-2026-a");
  expect(openYears()).toEqual(["2026"]);
  expect(page.years[2026].row.scrolled).toBe(0);
});

test("an unknown, empty or malformed hash does nothing and does not throw", () => {
  for (const hash of ["#nope", "#", "", "#%E0%A4%A"]) {
    expect(() => load(hash)).not.toThrow();
    expect(openYears()).toEqual(["2026"]);
  }
});

test("a later hashchange reveals the new target", () => {
  win.location.hash = "#pub-2025-a";
  win.fire("hashchange");
  expect(openYears()).toEqual(["2025", "2026"]);
  expect(page.years[2025].row.scrolled).toBe(1);
});

test("Expand all opens every year, and the same button then collapses them all", () => {
  page.button.fire("click");
  expect(openYears()).toEqual(["2024", "2025", "2026"]);
  expect(page.button.textContent).toBe("Collapse all");
  page.button.fire("click");
  expect(openYears()).toEqual([]);
  expect(page.button.textContent).toBe("Expand all");
});

test("the button label follows years opened or closed by hand", () => {
  page.years[2025].details.open = true;
  page.years[2025].details.fire("toggle");
  expect(page.button.textContent).toBe("Expand all");
  page.years[2024].details.open = true;
  page.years[2024].details.fire("toggle");
  expect(page.button.textContent).toBe("Collapse all");
  page.years[2024].details.open = false;
  page.years[2024].details.fire("toggle");
  expect(page.button.textContent).toBe("Expand all");
});
