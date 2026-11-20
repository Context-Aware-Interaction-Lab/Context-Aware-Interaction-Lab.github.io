// The phone layouts (max-width 640px): compact banner, one-row filters behind a Filters button, compact paper
// cards, a swipeable strip of Research cards. Numbers in the comments were measured on the real site at 390px
// before and after the change; the limits sit a little above the "after" so a regression toward the "before" fails.
import { test, expect, openAllYears, hasNoHorizontalScroll } from "./fixtures.js";

test.use({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });

test.describe("Publications on a phone", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/publications/");
    await expect(page.locator(".pub-filters")).toBeVisible(); // year-folds.js has run
  });

  // With the site's web fonts: 118px before, 53px after. These specs block the web fonts (see fixtures.js) and the
  // wider fallback font wraps the text onto a third line: about 72px after, about 135px before.
  test("the recruitment banner is one compact row, and Join Us keeps a 44px tap area", async ({ page }) => {
    const banner = await page.locator(".cta-banner--strip").boundingBox();
    expect(banner.height).toBeLessThanOrEqual(85);

    const visible = await page.locator(".cta-banner--strip .btn").boundingBox();
    expect(visible.height).toBeLessThan(44); // it looks smaller than the tap target on purpose
    const tapHeight = await page.evaluate(() => {
      const button = document.querySelector(".cta-banner--strip .btn");
      const box = button.getBoundingClientRect();
      const hits = y => {
        const found = document.elementFromPoint(box.left + box.width / 2, y);
        return !!found && (found === button || button.contains(found));
      };
      let top = box.top;
      let bottom = box.bottom;
      while (hits(top - 0.5)) top -= 0.5;
      while (hits(bottom + 0.5)) bottom += 0.5;
      return bottom - top;
    });
    expect(tapHeight).toBeGreaterThanOrEqual(44);
  });

  // 148px before (three lines), 44px after.
  test("search and one Filters button share a row; the chips wait behind it", async ({ page }) => {
    const row = await page.locator(".pub-filters__row").boundingBox();
    expect(row.height).toBeLessThanOrEqual(50);
    await expect(page.locator(".pub-filters__toggle")).toBeVisible();
    await expect(page.locator("#pub-search")).toBeVisible();
    await expect(page.locator(".pub-filters__panel")).toBeHidden();
    await expect(page.locator('button.chip[data-value="journal"]')).toBeHidden();
  });

  test("the Filters panel shows both menus' chips flat, counts them, and Escape closes it", async ({ page }) => {
    const toggle = page.locator(".pub-filters__toggle");
    await toggle.click();
    await expect(toggle).toHaveAttribute("aria-expanded", "true");
    for (const value of ["journal", "conference", "care", "multimodal", "other"]) {
      await expect(page.locator(`button.chip[data-value="${value}"]`)).toBeVisible();
    }
    await expect(page.locator(".year-controls__all")).toBeVisible();

    await page.locator('button.chip[data-value="journal"]').click();
    await expect(toggle.locator(".pub-menu__count")).toHaveText("1");
    await expect(page.locator(".pub-filters__status")).toHaveText(/^\d+ of 39 publications$/);
    expect(new URL(page.url()).searchParams.get("type")).toBe("journal");

    await page.keyboard.press("Escape");
    await expect(toggle).toHaveAttribute("aria-expanded", "false");
    await expect(page.locator(".pub-filters__panel")).toBeHidden();
    await expect(toggle).toBeFocused();
    await expect(toggle.locator(".pub-menu__count")).toHaveText("1"); // a closed panel still says it is filtering
  });

  test("resizing up to a desktop width with the panel open resets it to the popover menus", async ({ page }) => {
    await page.locator(".pub-filters__toggle").click();
    await expect(page.locator('button.chip[data-value="journal"]')).toBeVisible();
    await page.setViewportSize({ width: 1280, height: 900 });
    await expect(page.locator(".pub-filters__toggle")).toBeHidden();
    await expect(page.locator(".pub-filters")).not.toHaveClass(/is-open/);
    expect(await page.locator("details.pub-menu[open]").count()).toBe(0);
    await expect(page.locator(".pub-menu summary").first()).toBeVisible();
  });

  // Rows: 427px with a figure and 306px without before; 255px and 216px after; 13,639px in all, 8,959px after.
  test("a row is a compact card with the thumbnail beside the title", async ({ page }) => {
    await openAllYears(page);
    const stats = await page.evaluate(() => {
      const rows = [...document.querySelectorAll("li.publication-row")];
      const info = rows.map(row => ({ figure: row.hasAttribute("data-figure"), height: row.getBoundingClientRect().height }));
      const average = list => list.reduce((sum, i) => sum + i.height, 0) / list.length;
      return {
        rows: rows.length,
        withFigure: average(info.filter(i => i.figure)),
        withoutFigure: average(info.filter(i => !i.figure)),
        total: info.reduce((sum, i) => sum + i.height, 0),
      };
    });
    expect(stats.rows).toBe(39);
    expect(stats.withFigure).toBeLessThanOrEqual(285);
    expect(stats.withoutFigure).toBeLessThanOrEqual(250);
    expect(stats.total).toBeLessThanOrEqual(10_000);

    const row = page.locator("li.publication-row[data-figure]").first();
    const figure = await row.locator(".publication-row__figure").boundingBox();
    const title = await row.locator(".publication-row__title").boundingBox();
    const venue = await row.locator(".publication-row__venue").boundingBox();
    expect(figure.x + figure.width).toBeLessThanOrEqual(title.x + 1); // beside the title, not above it
    expect(Math.abs(figure.y - venue.y)).toBeLessThan(8); // level with the venue line
    expect(Math.round(figure.width)).toBe(96);
  });

  test("a row's labels and links share a footer, and nothing is hidden", async ({ page }) => {
    await openAllYears(page);
    const row = page.locator("li.publication-row").first();
    for (const part of [".publication-row__venue", ".publication-row__title", ".publication-row__authors", ".pub-labels", ".publication-row__links a"]) {
      await expect(row.locator(part).first()).toBeVisible();
    }
    const labels = await row.locator(".pub-labels").boundingBox();
    const links = await row.locator(".publication-row__links").boundingBox();
    expect(links.x).toBeGreaterThan(labels.x); // links at the right of the footer
    expect(links.y + links.height).toBeGreaterThanOrEqual(labels.y); // not above the labels
    const clipped = await row.locator(".publication-row__authors").evaluate(el => el.scrollHeight > el.clientHeight + 1);
    expect(clipped).toBe(false); // authors are never clamped
  });

  test("tapping a thumbnail opens the figure dialog", async ({ page }) => {
    await page.locator("#pub-chi26-acp-agent-roles .publication-row__figure").tap();
    await expect(page.locator("#figure-dialog")).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(page.locator("#figure-dialog")).toBeHidden();
  });

  test("a link into a closed year opens it and lands on the row", async ({ page }) => {
    await page.goto("/publications/#pub-dis24-emotions-mh");
    const row = page.locator("#pub-dis24-emotions-mh");
    await expect(row).toBeVisible();
    await expect.poll(async () => (await row.boundingBox()).y).toBeLessThan(300);
  });
});

test.describe("Research cards on a phone", () => {
  test.beforeEach(async ({ page }) => {
    // No #care here: a hash starts a smooth scroll, and geometry read while it runs is skewed.
    await page.goto("/research/");
  });

  // An area of three cards was 748-1,184px; a strip is one card tall.
  test("each area's cards are one strip, one card tall, with the next card peeking in", async ({ page }) => {
    const strips = page.locator(".paper-cards");
    const heights = await strips.evaluateAll(list => list.map(el => el.getBoundingClientRect().height));
    expect(heights).toHaveLength(3);
    heights.forEach(h => expect(h).toBeLessThanOrEqual(460));

    const peek = await page.evaluate(() => {
      const strip = document.querySelector(".paper-cards");
      const [first, second] = strip.querySelectorAll("li.paper-card");
      const widths = [first, second].map(el => el.getBoundingClientRect().width);
      const style = getComputedStyle(strip);
      return {
        snap: style.scrollSnapType,
        overflowX: style.overflowX,
        scrollable: strip.scrollWidth > strip.clientWidth,
        secondLeft: second.getBoundingClientRect().left,
        viewport: window.innerWidth,
        equalWidths: widths[0] === widths[1],
      };
    });
    expect(peek.snap).toContain("mandatory");
    expect(peek.overflowX).toBe("auto");
    expect(peek.scrollable).toBe(true);
    expect(peek.secondLeft).toBeLessThan(peek.viewport - 24); // some of the second card shows
    expect(peek.secondLeft).toBeGreaterThan(peek.viewport * 0.6); // but the first still dominates
    expect(peek.equalWidths).toBe(true);
  });

  test("a touch swipe moves the strip and snaps a card to the left edge", async ({ page }) => {
    const strip = page.locator("#care .paper-cards");
    // Scroll into view at once (not smoothly) and read where the strip landed in the same step.
    const y = await strip.evaluate(el => {
      el.scrollIntoView({ block: "center", behavior: "instant" });
      const box = el.getBoundingClientRect();
      return box.top + Math.min(100, box.height / 2);
    });
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Input.synthesizeScrollGesture", {
      x: 300, y, xDistance: -250, yDistance: 0, speed: 800, gestureSourceType: "touch",
    });
    await expect.poll(() => strip.evaluate(el => {
      const lefts = [...el.querySelectorAll("li.paper-card")].map(c => c.getBoundingClientRect().left);
      return el.scrollLeft > 0 && lefts.some(left => Math.abs(left - 16) <= 2);
    })).toBe(true);
  });

  test("tabbing to a card that is out of view scrolls the strip to it", async ({ page }) => {
    const strip = page.locator("#care .paper-cards");
    await page.locator("#care li.paper-card:last-child a").focus();
    await expect.poll(() => strip.evaluate(el => el.scrollLeft)).toBeGreaterThan(100);
  });

  test("a card still carries its type and area labels, pinned to its foot", async ({ page }) => {
    // All of it measured in one step, so nothing can move between one reading and the next.
    const cards = await page.evaluate(() => [...document.querySelectorAll("#care li.paper-card")].map(card => {
      const link = card.querySelector(".paper-card__link").getBoundingClientRect();
      const labels = card.querySelector(".pub-labels").getBoundingClientRect();
      return { typePills: card.querySelectorAll(".pill--type").length, fromFoot: link.bottom - labels.bottom, height: link.height };
    }));
    expect(cards.length).toBeGreaterThan(1);
    cards.forEach(card => expect(card.typePills).toBe(1));
    const feet = cards.map(card => card.fromFoot);
    // every card's labels sit the same distance from its foot, and the cards are one height
    expect(Math.max(...feet) - Math.min(...feet), `distances from each card's foot: ${feet}`).toBeLessThanOrEqual(1);
    expect(new Set(cards.map(card => Math.round(card.height))).size).toBe(1);
  });
});

test.describe("No horizontal scrolling at any narrow width", () => {
  for (const path of ["/publications/", "/research/", "/"]) {
    for (const width of [320, 375, 390, 640, 641]) {
      test(`${path} at ${width}px`, async ({ page }) => {
        await page.setViewportSize({ width, height: 844 });
        await page.goto(path);
        expect(await hasNoHorizontalScroll(page)).toBe(true);
      });
    }
  }
});
