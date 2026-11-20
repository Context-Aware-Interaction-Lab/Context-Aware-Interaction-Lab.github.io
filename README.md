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
- `_layouts/`, `_includes/` and the page files (`index.html`, `research.html`, `news.html`, `people.html`, `publications.html`, `join-us.html`, `gallery.html`) render it.
- `AGENTS.md` has the project facts for coding agents.

## Adding a gallery album

The Gallery (`/gallery/`) is live with one album. It is published exactly while `_data/gallery.yml` has an album: `GalleryVisibilityTest` fails if the page, its nav entry (just before Code) and the albums fall out of step, so emptying the list means putting `published: false` back in `gallery.html` and removing the nav entry. The components are shown on `/design-language/` (the specimen album).

1. Get consent first: everyone identifiable in the photos, and anyone named in a caption, has agreed to web use. Record the day as the album's `consent`.
2. Make the images, one call per photo (JPEG in; export a HEIC as JPEG first). It turns the EXIF rotation into real rotation, converts to sRGB, resizes, strips every metadata segment (location included), writes `assets/img/gallery/<album>/NN.jpg` and `NN-thumb.jpg` (the album's folder is created for you), and prints the `gallery.yml` line to paste:
   ```sh
   bin/figure photo chi26-barcelona 1 ~/Pictures/IMG_0412.jpg
   ```
3. Add the album to `_data/gallery.yml` (the header comment lists the fields). Alt text says what the photo shows; a caption naming someone is covered by the consent.
4. Nothing else to switch on: the page and nav entry already exist. Photos are sized by the tool (at most 1280px, 350 KB); `bin/check` refuses anything bigger.
5. Preview with `bundle exec jekyll serve --livereload`, then run `bin/check`.
