# cailab-website

Static Jekyll site for the Context-Aware Interaction Lab (CAILab) at SUTD, replacing the Google Site at cailab.info. Deployed by hand to GitHub Pages.

## Run

Needs Ruby 3.1.6 (see `.ruby-version`; Ruby 4.x does not work with the `github-pages` gem).

```sh
bundle config set --local path vendor/bundle
bundle install
bundle exec jekyll serve --livereload   # http://localhost:4000
bin/check                               # strict build + tests
```

## Layout

- `_data/` holds the content. Edit a data file to change what the site says.
- `_layouts/`, `_includes/` and the page files (`index.html`, `research.html`, `news.html`, `people.html`, `publications.html`, `join-us.html`) render it.
- `AGENTS.md` has the project facts for coding agents.
