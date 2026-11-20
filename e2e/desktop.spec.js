// Publications filter and search, labels and layout on desktop and tablet widths. The filter logic itself is unit
// tested in tests/year-folds.test.js against a stand-in DOM; these run the real script in a real browser.
import { test, expect, openAllYears } from "./fixtures.js";

// What the page itself says a row is: type and areas come from its data attributes, which Ruby tests tie to the data.
const rowFacts = page => page.evaluate(() => [...document.querySelectorAll("li.publication-row")].map(row => ({
  id: row.id,
  type: row.dataset.type,
  areas: row.dataset.areas.split(" "),
  text: row.dataset.text.normalize("NFD").replace(/[̀-ͯ]/g, ""),
  hidden: row.hidden,
  // Whether it is really drawn, which is what a visitor sees: `hidden` only works if no display rule beats it.
  rendered: row.getClientRects().length > 0,
  sectionHidden: row.closest("section").hidden,
})));

test.describe("Publications on a desktop", () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test.beforeEach(async ({ page }) => {
    await page.goto("/publications/");
    await expect(page.locator(".pub-filters")).toBeVisible();
  });

  test("search, Type, Research area and Expand all share one row", async ({ page }) => {
    const row = await page.locator(".pub-filters__row").boundingBox();
    expect(row.height).toBeLessThanOrEqual(50);
    await expect(page.locator(".pub-filters__toggle")).toBeHidden(); // the phone button is not shown here
    const centres = [];
    for (const locator of [page.locator("#pub-search"), page.locator('details[data-menu="type"] > summary'), page.locator('details[data-menu="area"] > summary'), page.locator(".year-controls__all")]) {
      await expect(locator).toBeVisible();
      const box = await locator.boundingBox();
      centres.push(box.y + box.height / 2);
    }
    expect(Math.max(...centres) - Math.min(...centres)).toBeLessThan(6);
  });

  test("a menu opens as a popover, counts its chips, and one open menu closes the other", async ({ page }) => {
    const type = page.locator('details[data-menu="type"]');
    const area = page.locator('details[data-menu="area"]');
    const firstYearBefore = await page.locator("details.year").first().boundingBox();
    await type.locator("summary").click();
    const summary = await type.locator("summary").boundingBox();
    const panel = await type.locator(".pub-menu__panel").boundingBox();
    expect(panel.y).toBeGreaterThanOrEqual(summary.y + summary.height); // below the button...
    const firstYearAfter = await page.locator("details.year").first().boundingBox();
    expect(firstYearAfter.y).toBeCloseTo(firstYearBefore.y, 0); // ...and floating over the page, not pushing it down
    await page.locator('button.chip[data-value="journal"]').click();
    await expect(type.locator(".pub-menu__count")).toHaveText("1");

    await area.locator("summary").click();
    await expect(type).not.toHaveAttribute("open", "");
    await expect(area).toHaveAttribute("open", "");

    await page.locator("h1").click();
    await expect(area).not.toHaveAttribute("open", ""); // a click outside closes it
    await type.locator("summary").click();
    await page.keyboard.press("Escape");
    await expect(type).not.toHaveAttribute("open", "");
    await expect(type.locator("summary")).toBeFocused();
  });

  test("chips in one group add up and different groups narrow, checked against every row", async ({ page }) => {
    await openAllYears(page);
    await page.locator('details[data-menu="type"] > summary').click();
    await page.locator('button.chip[data-value="journal"]').click();
    await page.locator('button.chip[data-value="conference"]').click();
    await page.locator('details[data-menu="area"] > summary').click();
    await page.locator('button.chip[data-value="care"]').click();

    const facts = await rowFacts(page);
    let shown = 0;
    for (const row of facts) {
      const expected = ["journal", "conference"].includes(row.type) && row.areas.includes("care");
      expect(row.hidden, `${row.id} should be ${expected ? "shown" : "hidden"}`).toBe(!expected);
      if (!row.sectionHidden) expect(row.rendered, `${row.id}: hidden=${row.hidden} but drawn=${row.rendered}`).toBe(!row.hidden);
      if (expected) shown += 1;
    }
    expect(shown).toBeGreaterThan(0);
    await expect(page.locator(".pub-filters__status")).toHaveText(`${shown} of 39 publications`);
    await expect(page.locator(".year-controls__all")).toBeHidden(); // Expand all makes no sense mid-filter
    await expect(page.locator(".pub-filters__clear")).toBeVisible();
  });

  test("search matches title, author and venue, ignoring case and accents", async ({ page }) => {
    await openAllYears(page);
    await page.locator("#pub-search").fill("PERRAULT");
    const facts = await rowFacts(page);
    for (const row of facts) expect(row.hidden, row.id).toBe(!row.text.includes("perrault"));
    expect(facts.some(row => !row.hidden)).toBe(true);
    expect(facts.some(row => row.hidden)).toBe(true);

    await page.locator("#pub-search").fill("zzzz-nothing-matches");
    await expect(page.locator(".pub-filters__status")).toHaveText("No publications match.");
  });

  test("the filter is in the address, restores from it, and Clear brings back the whole list", async ({ page }) => {
    await page.locator("#pub-search").fill("peer");
    await page.locator('details[data-menu="type"] > summary').click();
    await page.locator('button.chip[data-value="journal"]').click();
    const url = new URL(page.url());
    expect(url.searchParams.get("type")).toBe("journal");
    expect(url.searchParams.get("q")).toBe("peer");

    await page.goto(url.pathname + url.search);
    await expect(page.locator("#pub-search")).toHaveValue("peer");
    await expect(page.locator('button.chip[data-value="journal"]')).toHaveAttribute("aria-pressed", "true");
    await expect(page.locator(".pub-filters__status")).not.toHaveText("");

    await page.locator(".pub-filters__clear").click();
    expect(new URL(page.url()).search).toBe("");
    const facts = await rowFacts(page);
    expect(facts.filter(row => row.hidden)).toHaveLength(0);
    await expect(page.locator(".year-controls__all")).toBeVisible();
  });

  test("a link to a paper the filter is hiding clears the filter and lands on the paper", async ({ page }) => {
    await page.goto("/publications/?type=journal#pub-dis24-emotions-mh");
    const row = page.locator("#pub-dis24-emotions-mh");
    await expect(row).toBeVisible();
    await expect(page.locator('button.chip[data-value="journal"]')).toHaveAttribute("aria-pressed", "false");
    expect(new URL(page.url()).search).toBe("");
  });

  test("only the newest year starts open, and Expand all opens and closes them all", async ({ page }) => {
    expect(await page.locator("details.year[open]").count()).toBe(1);
    const all = page.locator(".year-controls__all");
    await expect(all).toHaveText("Expand all");
    await all.click();
    await expect(all).toHaveText("Collapse all");
    expect(await page.locator("details.year:not([open])").count()).toBe(0);
    await all.click();
    expect(await page.locator("details.year[open]").count()).toBe(0);
  });

  test("every row ends with one type pill and one area pill per area, and only award papers carry the medal", async ({ page }) => {
    await openAllYears(page);
    const rows = await page.evaluate(() => [...document.querySelectorAll("li.publication-row")].map(row => ({
      id: row.id,
      areas: row.dataset.areas.split(" ").filter(a => a !== "other"),
      typePills: row.querySelectorAll(".pill--type").length,
      areaPills: [...row.querySelectorAll(".pill--area")].map(p => p.dataset.area),
      award: row.querySelector(".publication-row__venue").textContent.includes("Honourable Mention"),
      medals: row.querySelectorAll(".medal").length,
    })));
    expect(rows).toHaveLength(39);
    for (const row of rows) {
      expect(row.typePills, row.id).toBe(1);
      expect(row.areaPills, row.id).toEqual(row.areas);
      expect(row.medals, row.id).toBe(row.award ? 1 : 0);
    }
    expect(rows.filter(r => r.award).length).toBeGreaterThanOrEqual(2);
  });

  test("the layout is the desktop one: three-column rows, side column, thumbnail dialog", async ({ page }) => {
    const row = page.locator("li.publication-row[data-figure]").first();
    expect(await row.evaluate(el => getComputedStyle(el).gridTemplateColumns.split(" ").length)).toBe(3);
    expect(await row.locator(".publication-row__side").evaluate(el => getComputedStyle(el).display)).toBe("flex");
    expect(Math.round((await row.locator(".publication-row__figure").boundingBox()).width)).toBe(168);
    await row.locator(".publication-row__figure").click();
    await expect(page.locator("#figure-dialog")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.locator("#figure-dialog")).toBeHidden();
  });

  test("the recruitment banner is a single centred line", async ({ page }) => {
    const banner = await page.locator(".cta-banner--strip").boundingBox();
    expect(banner.height).toBeLessThanOrEqual(70);
  });

  test("a year's type counts keep their names visible, and the page header keeps its generous padding", async ({ page }) => {
    const labels = await page.locator("details.year > summary").first().locator(".year__type-label").evaluateAll(
      list => list.map(el => ({ width: el.getBoundingClientRect().width, text: el.textContent.trim() })),
    );
    expect(labels.length).toBeGreaterThan(1);
    labels.forEach(label => expect(label.width).toBeGreaterThan(20));
    const paddingTop = await page.locator(".page-header").evaluate(el => parseFloat(getComputedStyle(el).paddingTop));
    expect(paddingTop).toBe(48);
  });
});

test.describe("Research cards on a desktop", () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test("cards sit in a three-column grid, each with the same labels as its publication row", async ({ page }) => {
    await page.goto("/research/");
    const cards = page.locator(".paper-cards").first();
    expect(await cards.evaluate(el => getComputedStyle(el).display)).toBe("grid");
    expect(await cards.evaluate(el => getComputedStyle(el).gridTemplateColumns.split(" ").length)).toBe(3);

    const labelled = await page.evaluate(() => [...document.querySelectorAll("li.paper-card")].map(card => ({
      id: card.querySelector("a").getAttribute("href").split("#pub-")[1],
      type: card.querySelector(".pill--type").textContent.trim(),
      areas: [...card.querySelectorAll(".pill--area")].map(p => p.dataset.area),
    })));
    expect(labelled.length).toBeGreaterThan(0);
    // The one-line "More" links keep their two columns here: venue on the left, title on the right.
    const link = page.locator("li.paper-link a").first();
    expect(await link.evaluate(el => getComputedStyle(el).gridTemplateColumns.split(" ").length)).toBe(2);
    await page.goto("/publications/");
    for (const card of labelled) {
      const row = page.locator(`#pub-${card.id}`);
      expect((await row.locator(".pill--type").textContent()).trim()).toBe(card.type);
      expect(await row.locator(".pill--area").evaluateAll(list => list.map(p => p.dataset.area))).toEqual(card.areas);
    }
  });
});

test.describe("Tablet width", () => {
  test.use({ viewport: { width: 768, height: 900 } });

  test("rows stay a single column with the figure above, and Research cards a two-column grid", async ({ page }) => {
    await page.goto("/publications/");
    const row = page.locator("li.publication-row[data-figure]").first();
    expect(await row.evaluate(el => getComputedStyle(el).gridTemplateColumns.split(" ").length)).toBe(1);
    expect(await row.locator(".publication-row__side").evaluate(el => getComputedStyle(el).display)).toBe("flex");
    expect(Math.round((await row.locator(".publication-row__figure").boundingBox()).width)).toBe(168);
    await expect(page.locator(".pub-filters__toggle")).toBeHidden();

    await page.goto("/research/");
    const cards = page.locator(".paper-cards").first();
    expect(await cards.evaluate(el => getComputedStyle(el).display)).toBe("grid");
    expect(await cards.evaluate(el => getComputedStyle(el).gridTemplateColumns.split(" ").length)).toBe(2);
  });
});
