# Project AGENTS.md — cailab-website

Software project workspace. Compact working memory — not a notebook. Move long material to separate files (README, docs/) and link.

## Orientation

Don't create or overwrite without confirmation unless explicitly asked to set up.

## Project snapshot

- What it is: Rebuild of the CAILab lab site (today a Google Site at cailab.info) as a static Jekyll site that Kenny deploys by hand to the lab's GitHub Pages and that AI harnesses can update cheaply.
- Language / runtime: Ruby 3.1.6 (`.ruby-version`, rbenv), Jekyll 3.10 via the `github-pages` gem. Not Homebrew Ruby 4.x: `github-pages` pins a liquid that breaks there. The shell must resolve `ruby` to 3.1.6 (rbenv shims first on PATH); `bin/check` fails loudly if not.
- How to run: `bundle exec jekyll serve --livereload` → http://localhost:4000. First time: `bundle config set --local path vendor/bundle && bundle install`.
- How to test: `bin/check` (strict Jekyll build, then Minitest in `tests/`).
- Lint / typecheck: none beyond the strict build in `bin/check`. Prettier can't parse Liquid, and no Ruby linter is added (dependency rule). The Python/JS gate table in `dev/AGENTS.md` doesn't cover this stack.
- Architecture: all content lives in `_data/*.yml` (lab, nav, news, people, publications, research, funding, media, join), looped over by six pages (`funding.yml` is kept but deliberately not rendered; `ResearchPageTest` guards that) through `_includes/` components. Tokens and components are in `assets/css/site.css` and documented on `/design-language/` (a hand-maintained page). `assets/js/rings.js` draws the name-seeded ring graphs and `assets/js/field.js` runs the hero canvas, with `_includes/field-static.html` as the no-JS fallback.
- Entrypoints / important files: `_config.yml`, `_data/`, `_layouts/default.html`, `_includes/`, the pages (`index.html`, `research.html`, `news.html`, `people.html`, `publications.html`, `join-us.html`, `design-language.html`), `assets/`, `bin/check`, `tests/site_test.rb`.
- Constraints / what to watch:
  - `exclude:` in `_config.yml` replaces Jekyll's defaults, so `Gemfile`, `Gemfile.lock` and the like must stay listed, and `theme: null` stops the gem publishing its own `assets/css/style.css`; `PublishedFilesTest` enforces both.
  - The old Google Site's `/home`, `/media` and `/funding` are redirect stubs (`home.html`, `media.html`, `funding.html`, via `jekyll-redirect-from`): meta-refresh pages, not server 301s. `/funding` goes to `/research/` because the Funding section is hidden. `OldUrlRedirectsTest` guards them.
  - `CNAME` (the production host) and `url:` in `_config.yml` must agree; `ProductionIdentityTest` guards both plus the canonical and Open Graph tags. `favicon.ico` and `assets/img/apple-touch-icon.png` are cut from the logo's sphere on white (a missing favicon logs a 404 on every first visit).
  - Pages builds with its own gem versions and runs no custom Ruby plugins. The local build says "will this obviously break", not byte-for-byte truth. Anything generated (field hero, name-seeded ring graphs) must be client-side JS with a no-JS fallback.
  - The only address in the HTML is the contact `mailto:` (Kenny's choice, in `_data/lab.yml`); it is never visible text and no other address may appear. Tested.
  - Only the director's photo is used (tested); add another person's photo only with their consent.
  - Data text was copied from the old site as written. News `text` and research/join bodies are Markdown. One news item has no date: it stays off the home preview but is listed on `/news/`.
  - The site is public: nothing under review or unpublished goes on it. `publications.yml` is hand-copied from the CV's `publications.bib` (never its `inreview` entries); `PublicContentTest` blocks any entry with no venue, year or public link, and any text reading as under submission.- External services / secrets needed: none locally.
- Deploy target: GitHub Pages from `main` of `Context-Aware-Interaction-Lab/Context-Aware-Interaction-Lab.github.io`, served at https://www.cailab.info (the `CNAME` file; DNS is managed outside this repo). Manual deploy; never push to `main` without Kenny's go-ahead after he has inspected the local render.
- Current status + next steps: Live. Done-gate exemption taken: `rings.js` and `field.js` have no automated tests. Next: keep `_data/` current.

## Standards & routing

Engineering practice for `dev/` — definition of done, testing, toolchain, dependencies, git hygiene — lives in `dev/AGENTS.md` and auto-loads. Don't restate it here. This file holds project facts only; project-specific constraints go in the snapshot above.

## File hygiene

Keep this file the compact map. Everything else — code, docs, config — lives normally in the repo.
