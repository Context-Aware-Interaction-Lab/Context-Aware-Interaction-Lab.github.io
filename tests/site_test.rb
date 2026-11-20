require "minitest/autorun"
require "cgi"
require "date"
require "fileutils"
require "open3"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)

# One real build shared by every test; the build is the slow part.
BUILD = begin
  dest = Dir.mktmpdir("cailab-site-")
  # after_run, not at_exit: autorun's own at_exit would otherwise fire second.
  Minitest.after_run { FileUtils.remove_entry(dest) }
  out, status = Open3.capture2e(
    "bundle", "exec", "jekyll", "build", "--strict_front_matter", "--destination", dest,
    chdir: ROOT
  )
  abort "jekyll build failed:\n#{out}" unless status.success?
  dest
end

def data(name) = YAML.safe_load(File.read(File.join(ROOT, "_data", "#{name}.yml")))

# Consent (2026-11-18, extended 2026-11-20): a photo already on the site stays with the person when a member
# becomes an alumnus or a collaborator becomes a former collaborator, and comes off on request. Nobody who never
# had one here is photographed without consent first. `.compact` matters: `collaborators_former` is absent from
# people.yml until someone moves, and a nil here would crash the suite when StrayFilesTest loads.
PHOTO_LISTS = %w[members collaborators collaborators_former alumni_graduate alumni_undergraduate].freeze
def photo_people = data("people").values_at(*PHOTO_LISTS).flatten.compact.select { |p| p["photo"] }

# Everyone who has left: alumni of both kinds plus former collaborators (the key may be absent).
def left_people = data("people").values_at("alumni_graduate", "alumni_undergraduate", "collaborators_former").flatten.compact

# Images are organised by purpose under assets/img: brand/ (logo, touch icon), people/ (photos), publications/ and
# gallery/<album>/. A publication may declare a figure and/or a video: publications/<slug>.jpg (large),
# <slug>-thumb.jpg, and for a video <slug>-poster.jpg.
def figure_pubs = data("publications").select { |p| p["figure"] }
def video_pubs = data("publications").select { |p| p["video"] }

def publication_images
  figure_pubs.flat_map { |p| ["publications/#{p["figure"]["slug"]}.jpg", "publications/#{p["figure"]["slug"]}-thumb.jpg"] } +
    video_pubs.map { |p| "publications/#{p["video"]["slug"]}-poster.jpg" }
end

# Gallery albums (gallery.yml) and the specimen album on /design-language/. A photo is
# assets/img/gallery/<album>/<file>.jpg with <file>-thumb.jpg beside it; StrayFilesTest and ImageMetadataTest recurse.
def gallery_albums = data("gallery")["albums"] || []
def gallery_images
  gallery_albums.flat_map { |a| a["photos"].flat_map { |p| ["gallery/#{a["slug"]}/#{p["file"]}.jpg", "gallery/#{a["slug"]}/#{p["file"]}-thumb.jpg"] } }
end

# JPEG structure without a dependency: [[marker, payload], ...] for the segments before the image data.
def jpeg_segments(path)
  bytes = File.binread(path)
  raise "not a JPEG: #{path}" unless bytes.start_with?("\xFF\xD8".b)
  pos = 2
  segments = []
  while pos < bytes.bytesize && bytes.getbyte(pos) == 0xFF
    marker = bytes.getbyte(pos + 1)
    break if [0xDA, 0xD9].include?(marker) # start of scan / end of image
    length = bytes.byteslice(pos + 2, 2).unpack1("n")
    segments << [marker, bytes.byteslice(pos + 4, length - 2)]
    pos += 2 + length
  end
  segments
end

def jpeg_size(path)
  _, frame = jpeg_segments(path).find { |marker, _| [0xC0, 0xC1, 0xC2].include?(marker) }
  height, width = frame.byteslice(1, 4).unpack("nn")
  [width, height]
end

NAV = data("nav")
INTERNAL_PAGES = NAV.reject { |n| n["external"] }.map { |n| n["url"] }
PAGES = (["/"] + INTERNAL_PAGES + ["/design-language/"]).freeze

def html_of(page)
  file = page == "/" ? "index.html" : File.join(page, "index.html")
  File.read(File.join(BUILD, file))
end

def text_of(page) = html_of(page).gsub(/<[^>]+>/, " ").gsub(/\s+/, " ")

def count_of(page, css_class) = html_of(page).scan(/<li class="#{css_class}[ "]/).size

# Rendered text with entities decoded and typographic quotes straightened, for comparing against data.
def plain(str) = CGI.unescapeHTML(str).tr("\u2018\u2019\u201C\u201D", "''\"\"").gsub(/\s+/, " ")

# A real address: letter-led domain and a 2+ letter TLD (the Google Fonts URL has "wght@12..96").
EMAIL = /[\w.+-]+@[A-Za-z][\w-]*(\.[A-Za-z][\w-]*)*\.[A-Za-z]{2,}/

def emails_in(str) = str.to_enum(:scan, EMAIL).map { Regexp.last_match[0] }

# Kenny chose this address for the contact button (2026-11-18).
CONTACT_ADDRESS = "kennytwchoo@gmail.com".freeze

# assert_includes dumps the whole page on failure; these keep the message short.
def assert_has(haystack, needle, msg) = assert(haystack.include?(needle), msg)
def refute_has(haystack, needle, msg) = refute(haystack.include?(needle), msg)

class PublishedFilesTest < Minitest::Test
  # Setting `exclude:` in Jekyll 3 replaces its defaults, so these must be listed by hand.
  INTERNAL = %w[Gemfile Gemfile.lock AGENTS.md CLAUDE.md README.md tests bin design-demos vendor
                package.json bun.lock bunfig.toml node_modules e2e playwright.config.js test-results playwright-report].freeze

  def test_repo_internals_are_not_published
    leaked = INTERNAL.select { |name| File.exist?(File.join(BUILD, name)) }
    assert_empty leaked, "published but should not be: #{leaked.join(', ')}"
  end

  def test_only_our_stylesheet_is_published
    sheets = Dir.glob(File.join(BUILD, "**", "*.css")).map { |f| f.sub("#{BUILD}/", "") }
    assert_equal ["assets/css/site.css"], sheets
  end
end

# On a phone the links collapse behind a Menu button. The button starts `hidden` and nav.js reveals it, so a
# visitor without JS gets the plain links and never a dead button. Layout is checked in a browser (see AGENTS.md).
class NavMenuTest < Minitest::Test
  def test_every_page_has_a_hidden_menu_button_wired_to_the_link_list
    PAGES.each do |page|
      html = html_of(page)
      button = html[/<button[^>]*class="nav__toggle"[^>]*>/]
      refute_nil button, "no menu button on #{page}"
      assert_match(/aria-expanded="false"/, button, "closed at load on #{page}")
      assert_match(/\bhidden\b/, button, "button must start hidden on #{page}")
      target = button[/aria-controls="([^"]+)"/, 1]
      refute_nil target, "button controls nothing on #{page}"
      assert_match(/<ul[^>]*id="#{Regexp.escape(target)}"/, html, "no list with id #{target} on #{page}")
    end
  end

  def test_every_page_loads_the_menu_script_and_it_is_published
    assert File.exist?(File.join(BUILD, "assets/js/nav.js")), "nav.js not published"
    PAGES.each { |page| assert_has html_of(page), 'src="/assets/js/nav.js"', "nav.js on #{page}" }
  end

  def test_links_stay_in_the_markup_for_visitors_without_js
    PAGES.each do |page|
      list = html_of(page)[%r{<ul[^>]*id="nav-links".*?</ul>}m]
      refute_nil list, "no link list on #{page}"
      assert_equal NAV.map { |i| i["url"] }, list.scan(/<a href="([^"]+)"/).flatten, "nav links on #{page}"
    end
  end
end

class EveryPageTest < Minitest::Test
  def test_every_page_is_built
    PAGES.each { |page| assert html_of(page), "missing #{page}" }
  end

  def test_nav_links_to_every_section_on_every_page
    PAGES.each do |page|
      INTERNAL_PAGES.each do |url|
        assert_has html_of(page), %(href="#{url}"), "#{page} has no nav link to #{url}"
      end
    end
  end

  # The address may sit in a mailto: link, never as visible text, and no other address may appear.
  def test_only_the_contact_address_appears_and_never_as_visible_text
    PAGES.each do |page|
      assert_empty emails_in(html_of(page)) - [CONTACT_ADDRESS], "unexpected address on #{page}"
      assert_empty emails_in(text_of(page)), "address shown as text on #{page}"
    end
  end

  def test_contact_button_opens_a_mail_to_the_contact_address
    PAGES.each do |page|
      assert_has html_of(page), %(href="mailto:#{CONTACT_ADDRESS}"), "#{page} has no contact link"
    end
  end

  def test_footer_has_no_stale_2023
    PAGES.each do |page|
      footer = html_of(page)[%r{<footer.*?</footer>}m]
      refute_has footer, "2023", "stale year in footer of #{page}"
    end
  end

  def test_no_unrendered_template_syntax
    PAGES.each do |page|
      refute html_of(page).match?(/\{\{|\{%/), "unrendered Liquid on #{page}"
    end
  end

  def test_internal_links_and_anchors_resolve
    PAGES.each do |page|
      html = html_of(page)
      html.scan(/href="([^"]+)"/).flatten.each do |href|
        next if href == "#" || href.start_with?("http", "mailto:")
        if href.start_with?("#")
          assert_has html, %(id="#{href[1..]}"), "#{page}: dead anchor #{href}"
        else
          path, fragment = href.split("#")
          target = File.join(BUILD, path.end_with?("/") ? File.join(path, "index.html") : path)
          assert File.exist?(target), "#{page}: dead link #{href}"
          next unless fragment && target.end_with?(".html")
          assert_has File.read(target), %(id="#{fragment}"), "#{page}: #{href} points at a missing anchor"
        end
      end
    end
  end
end

# A moved or renamed image leaves a broken <img> that no link check sees.
class EveryImageTest < Minitest::Test
  def test_every_image_on_every_page_exists
    (PAGES + ["/design-language/"]).uniq.each do |page|
      html_of(page).scan(/<img\b[^>]*\bsrc="([^"]+)"/).flatten.each do |src|
        next if src.start_with?("http", "data:")
        assert File.size?(File.join(BUILD, src.split("?").first)), "#{page}: broken image #{src}"
      end
    end
  end

  def test_the_images_are_organised_by_purpose
    top = Dir.children(File.join(ROOT, "assets", "img")).reject { |f| f.start_with?(".") }.sort
    assert_equal %w[brand gallery people publications], top, "assets/img holds only the four purpose folders"
  end
end

class HomePageTest < Minitest::Test
  LAB = data("lab")

  def test_renders_lab_name_and_mission_from_data
    assert_has text_of("/"), LAB["name"], "home lacks the lab name"
    assert_has text_of("/"), LAB["mission"], "home lacks the mission"
  end

  # One short label on every contact button: menu bar, hero, director card, Join Us.
  def test_every_contact_button_reads_contact_us
    PAGES.each do |page|
      labels = html_of(page).scan(%r{<a class="btn[^"]*" href="mailto:[^"]*">([^<]*)</a>}).flatten
      refute_empty labels, "no contact button on #{page}"
      assert_equal ["Contact Us"], labels.uniq, "contact label on #{page}"
    end
  end

  def test_contact_buttons_exist_where_expected
    %w[/ /people/ /join-us/].each do |page|
      assert_operator html_of(page).scan(%r{<a class="btn[^"]*" href="mailto:}).size, :>=, 2, "expected nav plus page button on #{page}"
    end
  end

  def test_shows_the_recruitment_call_on_every_page
    PAGES.each { |page| assert_has text_of(page), LAB["recruitment"], "#{page} lacks the recruitment call" }
  end

  # The tiles are the research areas, defined once in research.yml, each opening its section on /research/.
  def test_lists_every_research_area_and_links_to_it
    html = html_of("/")
    areas = data("research")["areas"]
    assert_equal areas.size, html.scan('<li class="project-block"').size, "tile count"
    areas.each do |a|
      assert_has text_of("/"), a["title"], "home lacks area: #{a["title"]}"
      assert_has html, %(href="/research/##{a["slug"]}"), "tile for #{a["title"]} does not open its area"
    end
  end

  def test_mission_names_the_umbrella
    assert_has plain(text_of("/")), "Human-Centred AI", "home mission lacks the umbrella"
  end

  def test_previews_the_six_latest_dated_news_items
    dated = data("news").select { |n| n["date"] }
    assert_equal [6, dated.size].min, count_of("/", "news-item")
    dated.first(6).each { |n| assert_has text_of("/"), n["date"], "home lacks #{n["date"]}" }
  end

  def test_undated_announcements_stay_off_the_preview_but_on_the_news_page
    undated = data("news").reject { |n| n["date"] }
    refute_empty undated, "data no longer has an undated item; revisit this test"
    assert_equal data("news").size, count_of("/news/", "news-item")
    assert_operator count_of("/", "news-item"), :<=, data("news").size - undated.size
  end

  def test_hero_has_a_live_field_and_a_no_script_fallback
    html = html_of("/")
    assert_has html, '<canvas class="field"', "no live field"
    assert_has html, 'class="field-static"', "no no-script fallback field"
    assert_has html, "/assets/js/field.js", "field script not loaded"
  end

  def test_other_pages_do_not_load_the_field_script
    (PAGES - ["/"]).each { |page| refute_has html_of(page), "field.js", "#{page} loads field.js" }
  end
end

# Each home card leads to its full card on /news/. The anchor is counted from the oldest item,
# so news added at the top never moves an older link.
class NewsLinksTest < Minitest::Test
  NEWS = data("news")

  def anchor_for(index) = "news-#{NEWS.size - index}"

  def home_cards = html_of("/").split('<li class="news-item')[1..]

  def home_indexes = NEWS.each_index.select { |i| NEWS[i]["date"] }.first(6)

  def test_news_page_cards_carry_anchors_counted_from_the_oldest
    ids = html_of("/news/").scan(/<li class="news-item[^"]*" id="(news-\d+)"/).flatten
    assert_equal NEWS.each_index.map { |i| anchor_for(i) }, ids
  end

  def test_each_home_card_links_to_its_own_card_on_the_news_page
    hrefs = home_cards.map { |c| c[%r{<a class="news-item__more" href="([^"]+)"}, 1] }
    assert_equal home_indexes.map { |i| "/news/##{anchor_for(i)}" }, hrefs
  end

  def test_every_home_link_lands_on_an_existing_anchor
    ids = html_of("/news/").scan(/ id="(news-\d+)"/).flatten
    home_cards.each do |card|
      fragment = card[%r{<a class="news-item__more" href="/news/#([^"]+)"}, 1]
      assert_includes ids, fragment, "home link points at a missing anchor"
    end
  end

  def test_the_link_names_the_card_it_opens
    home_indexes.zip(home_cards).each do |i, card|
      label = card[%r{<a class="news-item__more".*?</a>}m]
      assert_match(/visually-hidden[^>]*>[^<]*#{Regexp.escape(NEWS[i]["date"])}/, label, "unnamed link for #{NEWS[i]["date"]}")
    end
  end

  def test_news_page_cards_do_not_link_to_themselves
    refute_has html_of("/news/"), "news-item__more", "self-link on /news/"
  end

  def test_links_inside_a_card_stay_clickable
    first = home_cards.first
    url = NEWS[home_indexes.first]["text"][%r{\]\((https?://[^)]+)\)}, 1]
    assert url, "first news item has no link; revisit this test"
    assert_has first, %(href="#{url}"), "link inside the card was lost"
  end

  def test_no_link_is_nested_inside_another
    PAGES.each do |page|
      refute_match(%r{<a\b[^>]*>(?:(?!</a>).)*<a\b}m, html_of(page), "nested link on #{page}")
    end
  end
end

class NewsPageTest < Minitest::Test
  def test_lists_every_announcement
    assert_equal data("news").size, count_of("/news/", "news-item")
  end

  # Whichever item has bullets in its data must render them as a list (the newest item need not).
  def test_nested_bullets_render_as_lists
    news = data("news")
    index = news.index { |n| n["text"].match?(/^- /) }
    assert index, "no news item has bullets; revisit this test"
    body = html_of("/news/").scan(%r{<div class="news-item__text">(.*?)</div>}m)[index].first
    assert_has body, "<ul>", "news item #{index} has no list"
    assert_has body, "<li>", "news item #{index} has no list items"
  end
end

class PublicationsPageTest < Minitest::Test
  def test_one_row_per_publication
    assert_equal data("publications").size, count_of("/publications/", "publication-row")
  end

  # ACM DOIs must be complete: a cut-off suffix 404s. Real ones end in 7 digits.
  def test_acm_dois_are_not_truncated
    short = data("publications").flat_map { |pub| pub["links"].map { |l| l["url"] } }
      .select { |url| url =~ %r{doi\.org/10\.1145/\d+\.(\d+)\z} && $1.size < 7 }
    assert_empty short, "truncated ACM DOI(s): #{short.join(', ')}"
  end

  def test_every_title_and_link_is_present
    text = text_of("/publications/")
    html = html_of("/publications/")
    data("publications").each do |pub|
      assert_has text, pub["title"], "missing publication: #{pub["title"]}"
      pub["links"].each { |link| assert_has html, %(href="#{link["url"]}"), "missing link #{link["url"]}" }
    end
  end

  # One heading per year, newest first, with every paper under the heading of its own year.
  def test_publications_are_grouped_under_year_headings
    walk = html_of("/publications/").scan(%r{<h2>(\d{4})</h2>|<h3 class="publication-row__title">(.*?)</h3>}m)
    headings = walk.map(&:first).compact.map(&:to_i)
    assert_equal data("publications").map { |p| p["year"] }.uniq, headings, "year headings missing or out of order"

    year = nil
    placed = walk.each_with_object({}) do |(heading, title), acc|
      heading ? year = heading.to_i : acc[title] = year
    end
    data("publications").each do |pub|
      assert_equal pub["year"], placed[pub["title"]], "under the wrong year heading: #{pub["title"]}"
    end
  end

  # Each year is a native <details> fold; only the newest starts open (assets/js/year-folds.js reveals the
  # rest when a link such as /publications/#pub-<id> points into a closed year).
  YEAR_FOLD = %r{<details class="year"([^>]*)>(.*?)</details>}m

  def year_folds
    html_of("/publications/").scan(YEAR_FOLD).map { |attrs, body| [attrs, body, body[%r{<h2>(\d{4})</h2>}, 1].to_i] }
  end

  def test_only_the_newest_year_starts_open
    open_years = year_folds.select { |attrs, _, _| attrs.match?(/\bopen\b/) }.map(&:last)
    assert_equal [data("publications").map { |p| p["year"] }.max], open_years, "only the newest year should start open"
  end

  def test_every_year_is_a_fold_that_holds_its_papers_and_states_their_count
    groups = data("publications").group_by { |p| p["year"] }
    folds = year_folds
    assert_equal groups.keys.sort.reverse, folds.map(&:last), "year folds missing or out of order"
    folds.each do |_, body, year|
      n = groups[year].size
      summary = body[%r{<summary>.*?</summary>}m] or flunk("#{year} fold has no summary")
      assert_has summary, "#{n} #{n == 1 ? "publication" : "publications"}", "#{year} summary has the wrong count"
      assert_equal n, body.scan('<li class="publication-row"').size, "#{year} fold holds the wrong rows"
    end
    assert_equal data("publications").size, folds.sum { |_, body, _| body.scan('<li class="publication-row"').size }, "a row sits outside every fold"
  end

  def test_year_sections_keep_their_year_anchor
    data("publications").map { |p| p["year"] }.uniq.each do |year|
      assert_has html_of("/publications/"), %(id="#{year}"), "#{year} anchor lost"
    end
  end

  def test_year_folds_script_and_a_hidden_expand_all_button
    html = html_of("/publications/")
    assert_has html, 'src="/assets/js/year-folds.js"', "year-folds.js not included"
    assert File.exist?(File.join(BUILD, "assets/js/year-folds.js")), "year-folds.js not published"
    assert html.include?('<button type="button" class="year-controls__all" hidden>Expand all</button>'),
      "Expand all button missing, or not hidden until the script reveals it"
  end

  def test_year_fold_is_listed_on_the_design_language_page
    assert_has html_of("/design-language/"), "<code>.year</code>", ".year not listed in Components"
  end
end

# Filter and search on /publications/ (assets/js/year-folds.js, behaviour in tests/year-folds.test.js).
# Every row carries what the script filters on. `type` is copied from the keywords of the CV's
# publications.bib, so the site and the CV sort the same paper the same way. (A "Selected" chip was tried and
# dropped, 2026-11-20: nothing told a visitor who selected what, and four papers is too few to need a filter.)
class PublicationFiltersTest < Minitest::Test
  PUBS = data("publications")
  TYPES = data("publication_types")
  BIB = File.expand_path("../../personal/cv/publications.bib", ROOT)

  def attrs_of_rows = html_of("/publications/").scan(%r{<li class="publication-row"([^>]*)>}).flatten

  def attr(attrs, name) = attrs[/ #{name}="([^"]*)"/, 1]

  def expected_areas(pub)
    slugs = data("research")["areas"]
      .select { |a| ((a["papers"] || []) + (a["more"] || [])).include?(pub["id"]) }.map { |a| a["slug"] }
    slugs.empty? ? "other" : slugs.join(" ")
  end

  def test_the_types_are_the_cv_keywords_and_every_publication_has_one
    assert_equal %w[journal conference chapter extended preprint], TYPES.map { |t| t["id"] }
    TYPES.each do |t|
      assert t["label"].to_s.size.positive? && t["short"].to_s.size.positive?, "type #{t["id"]} needs a label and a short"
      assert_includes (0..6).to_a, t["tone"], "type #{t["id"]} needs a tone: 0 (neutral grey) or 1-6 (the spectrum, .c1-.c6)"
    end
    assert_equal TYPES.size, TYPES.map { |t| t["tone"] }.uniq.size, "two types share a colour"
    PUBS.each do |pub|
      assert_includes TYPES.map { |t| t["id"] }, pub["type"], "unknown or missing type: #{pub["title"]}"
      refute pub.key?("selected"), "the dropped `selected` flag is back: #{pub["title"]}"
    end
  end

  # Matched by title, so a wrong keyword on the site fails here when the CV repo sits beside this one.
  def test_types_match_the_cv_bib
    skip "personal/cv/publications.bib not present: types not cross-checked" unless File.exist?(BIB)
    squash = ->(s) { s.to_s.delete("{}\\").downcase.gsub(/[^a-z0-9]/, "") }
    bib = File.read(BIB).scan(/@\w+\{[^,]+,(.*?)\n\}/m).map do |(body)|
      [squash.(body[/\btitle\s*=\s*\{(.*?)\},?\s*\n/m, 1]), (body[/keywords\s*=\s*\{([^}]*)\}/, 1] || "").split(",").map(&:strip)]
    end.to_h
    PUBS.each do |pub|
      keywords = bib[squash.(pub["title"])] or flunk("no entry in publications.bib for: #{pub["title"]}")
      refute_includes keywords, "inreview", "work under review is on the site: #{pub["title"]}"
      assert_includes keywords, pub["type"], "type disagrees with the bib keywords #{keywords}: #{pub["title"]}"
    end
  end

  def test_every_row_carries_its_type_areas_and_search_text
    rows = attrs_of_rows
    assert_equal PUBS.size, rows.size
    PUBS.zip(rows) do |pub, attrs|
      assert_equal pub["type"], attr(attrs, "data-type"), "data-type: #{pub["title"]}"
      assert_equal expected_areas(pub), attr(attrs, "data-areas"), "data-areas: #{pub["title"]}"
      assert_nil attr(attrs, "data-selected"), "data-selected is back: #{pub["title"]}"
      expected = plain([pub["title"], pub["authors"], pub["venue"]].join(" ")).downcase
      assert_equal expected, plain(attr(attrs, "data-text").to_s), "data-text: #{pub["title"]}"
    end
  end

  # Research areas wear pastels (research.yml `pastel`, 1-7), a palette of their own: the saturated spectrum
  # belongs to paper types and graphics. The design language defines seven, so seven areas at most.
  def test_each_area_has_a_short_name_and_its_own_pastel
    areas = data("research")["areas"]
    assert_operator areas.size, :<=, 7, "the design language has pastels for up to 7 research areas"
    areas.each do |a|
      assert a["short"].to_s.size.positive?, "area #{a["slug"]} needs a short name for its pill"
      assert_includes (1..7).to_a, a["pastel"], "area #{a["slug"]} needs a pastel 1-7 (.a1-.a7)"
      refute a.key?("tone"), "area #{a["slug"]} still has the retired spectrum `tone`"
    end
    assert_equal areas.size, areas.map { |a| a["pastel"] }.uniq.size, "two areas share a pastel"
  end

  # --area-N-bg / -edge / -dot in site.css, one .aN class per slot, and a swatch for each on the design language
  # page that shows the same hex values, so the page cannot drift from the stylesheet.
  def test_the_stylesheet_and_design_language_define_seven_area_pastels
    css = File.read(File.join(BUILD, "assets/css/site.css"))
    design = html_of("/design-language/")
    assert_has design, "up to 7 research areas", "the design language should say how many areas the pastels cover"
    (1..7).each do |n|
      hexes = %w[bg edge dot].map do |part|
        css[/--area-#{n}-#{part}:(#\h{6})/, 1] or flunk("--area-#{n}-#{part} is not defined in site.css")
      end
      assert_match(/\.a#{n}\{/, css, ".a#{n} is not defined in site.css")
      assert_has design, "<code>--area-#{n}</code>", "--area-#{n} has no swatch on /design-language/"
      hexes.each { |hex| assert_has design.upcase, hex.upcase, "/design-language/ does not show #{hex} of --area-#{n}" }
    end
  end

  # The label strip under a paper's authors (publication row) and at the foot of its Research card: its type
  # pill (the type's dot and short name, publication_types.yml), then one pastel pill per research area it sits
  # in, in research.yml order and none when it sits in no area (research.yml: slug, pastel, short).
  def expected_labels(pub)
    type = TYPES.find { |t| t["id"] == pub["type"] }
    areas = data("research")["areas"].select { |a| ((a["papers"] || []) + (a["more"] || [])).include?(pub["id"]) }
    { type: [type["tone"], type["short"]], areas: areas.map { |a| [a["slug"], a["pastel"], a["short"]] } }
  end

  def labels_in(fragment)
    strip = fragment[%r{<div class="pub-labels">(.*?)</div>}m, 1] or return nil
    type = strip.match(%r{<span class="pill pill--type"><span class="dot c(\d)" aria-hidden="true"></span>([^<]*)</span>})
    areas = strip.scan(%r{<span class="pill pill--area a(\d)" data-area="([^"]+)">([^<]*)</span>})
    { type: type && [type[1].to_i, CGI.unescapeHTML(type[2])],
      areas: areas.map { |pastel, slug, text| [slug, pastel.to_i, CGI.unescapeHTML(text)] } }
  end

  def test_each_row_ends_with_its_type_and_area_labels
    html = html_of("/publications/")
    rows = html.scan(%r{<li class="publication-row".*?</li>}m)
    assert_equal PUBS.size, rows.size
    PUBS.zip(rows) { |pub, row| assert_equal expected_labels(pub), labels_in(row), "labels: #{pub["title"]}" }
    refute_match(/publication-row__type/, html, "the old side-column type badge is still there")
    refute_match(%r{publication-row__venue"><span class="dot}, html, "the type dot should live in the pill, not the venue line")
  end

  def test_each_research_card_carries_the_same_labels_as_its_row
    cards = html_of("/research/").scan(%r{<li class="paper-card">.*?</li>}m)
    refute_empty cards
    cards.each do |card|
      id = card[%r{href="/publications/#pub-([^"]+)"}, 1]
      pub = PUBS.find { |p| p["id"] == id } or flunk("card for unknown paper #{id}")
      assert_equal expected_labels(pub), labels_in(card), "card labels: #{id}"
    end
  end

  # A medal follows the venue of every Honourable Mention paper, wherever a venue is printed (publication row,
  # research paper card and link), and no other. The `venue` string itself is untouched: JoinApplyTest matches it.
  VENUE = %r{<(p|span) class="(?:publication-row__venue|paper-card__venue|paper-link__venue)">((?:[^<]|<span[^>]*></span>|<span class="medal"[^>]*>[^<]*</span>)*)</\1>}

  def test_honourable_mention_papers_get_a_medal_and_no_others_do
    %w[/publications/ /research/].each do |page|
      venues = html_of(page).scan(VENUE).map(&:last)
      honoured = venues.select { |v| v.include?("Honourable Mention") }
      assert_operator honoured.size, :>=, 2, "#{page}: expected the two CHI'26 Honourable Mention venues"
      venues.each do |v|
        if v.include?("Honourable Mention")
          assert_includes v, '<span class="medal" aria-hidden="true">🏅</span>', "#{page}: no medal on #{v[0, 40]}"
        else
          refute_includes v, "medal", "#{page}: medal on a paper without an award: #{v[0, 40]}"
        end
      end
    end
  end

  # Expand all shares the row with the search box. Clear (while filtering) and Expand all (when not) take the
  # same slot, which year-folds.js swaps, so the row never grows a second line of controls.
  def test_expand_all_sits_in_the_filter_row
    html = html_of("/publications/")
    row = html[%r{<div class="pub-filters__row">.*?<p class="pub-filters__status"}m] or flunk("no filter row")
    assert_has row, '<button type="button" class="year-controls__all" hidden>Expand all</button>', "Expand all is not in the filter row"
    assert_has row, 'id="pub-search"', "the search box is not in the same row"
    refute_match(/class="container year-controls"/, html, "the standalone Expand all container is still there")
  end

  # On phones (max-width 640px, year-folds.js) the menus sit behind one Filters button: the toggle follows the
  # search box, and the panel it controls holds both menus, Clear and Expand all. Above 640px the panel is
  # display:contents, so the row is unchanged.
  def test_a_filters_toggle_controls_a_panel_holding_the_menus_clear_and_expand_all
    html = html_of("/publications/")
    row = html[%r{<div class="pub-filters__row">.*?<p class="pub-filters__status"}m] or flunk("no filter row")
    toggle = '<button type="button" class="pub-filters__toggle" aria-expanded="false" aria-controls="pub-filters-panel">Filters<span class="pub-menu__count" hidden></span></button>'
    assert_has row, toggle, "the Filters toggle is missing or malformed"
    panel_at = row.index('<div class="pub-filters__panel" id="pub-filters-panel">') or flunk("no #pub-filters-panel")
    assert_operator row.index('id="pub-search"'), :<, row.index(toggle), "the toggle must follow the search box"
    assert_operator row.index(toggle), :<, panel_at, "the toggle must come before the panel it controls"
    panel = row[panel_at..]
    %w[type area].each { |m| assert_has panel, %(<details class="pub-menu" data-menu="#{m}">), "the #{m} menu is not inside the panel" }
    assert_has panel, 'class="pub-filters__clear"', "Clear is not inside the panel"
    assert_has panel, 'class="year-controls__all"', "Expand all is not inside the panel"
    refute_has row[0...panel_at], 'class="pub-menu"', "a menu sits outside the panel"
  end

  def test_the_filter_bar_is_hidden_until_the_script_reveals_it
    html = html_of("/publications/")
    bar = html[%r{<div class="[^"]*\bpub-filters\b[^"]*"[^>]*>}] or flunk("no .pub-filters bar")
    assert_match(/\bhidden\b/, bar, "the filter bar must be hidden in the HTML (no dead controls without JavaScript)")
    assert_match(%r{<input type="search" id="pub-search"}, html)
    assert_match(%r{<label [^>]*for="pub-search">Search publications</label>}, html)
    assert_match(%r{class="pub-filters__status"[^>]*aria-live="polite"}, html)
    assert_match(%r{class="pub-filters__clear"[^>]*hidden}, html, "Clear starts hidden")
  end

  def test_there_is_a_chip_for_each_type_in_use_each_area_and_other_and_no_selected_chip
    html = html_of("/publications/")
    # A chip is [dot colour class or nil, label]: a type chip carries its type's dot ("c6", the spectrum), an
    # area chip its area's pastel dot ("a3") and the neutral "Other" chip none.
    chip = lambda do |group, value|
      # An area chip also carries its pastel class on the button, which the stylesheet tints it with.
      m = html.match(%r{<button type="button" class="chip(?: a\d)?" aria-pressed="false" data-filter="#{group}" data-value="#{value}">(?:<span class="dot ([ac]\d)" aria-hidden="true"></span>)?([^<]*)</button>})
      m && [m[1], CGI.unescapeHTML(m[2])]
    end
    used = PUBS.map { |p| p["type"] }.uniq
    TYPES.each do |t|
      if used.include?(t["id"])
        assert_equal ["c#{t["tone"]}", t["label"]], chip.("type", t["id"]), "type chip (dot colour, label): #{t["id"]}"
      else
        assert_nil chip.("type", t["id"]), "chip for a type with no publications: #{t["id"]}"
      end
    end
    data("research")["areas"].each do |a|
      assert_equal ["a#{a["pastel"]}", a["title"]], chip.("area", a["slug"]), "area chip (dot colour, full title): #{a["slug"]}"
    end
    assert_equal [nil, "Other"], chip.("area", "other")
    refute_match(/data-filter="selected"/, html, "the Selected chip was dropped")
  end

  # Each year's mix of types, one entry per type present: the type's dot, the count, and the type's name. The name
  # is its own span so a phone can hide it visually (dots and numbers only) while it stays in the page for screen
  # readers, and the whole entry carries it as a tooltip.
  def test_each_year_summary_breaks_the_year_down_by_type_in_the_type_colours
    summaries = html_of("/publications/").scan(%r{<summary><h2>(\d{4})</h2>(.*?)</summary>}m)
    assert_equal PUBS.map { |p| p["year"] }.uniq.size, summaries.size
    summaries.each do |year, inner|
      papers = PUBS.select { |p| p["year"] == year.to_i }
      expected = TYPES.map { |t| [t, papers.count { |p| p["type"] == t["id"] }] }.reject { |_, n| n.zero? }
        .map { |t, n| [t["tone"], "#{n} #{t["short"]}"] }
      types_html = inner[%r{<span class="year__types">(.*)</span>\z}m, 1] or flunk("#{year} has no .year__types")
      entries = types_html.scan(%r{<span class="year__type" title="([^"]*)"><span class="dot c(\d)" aria-hidden="true"></span>(\d+) <span class="year__type-label">([^<]*)</span></span>})
      actual = entries.map { |_, tone, n, label| [tone.to_i, "#{n} #{CGI.unescapeHTML(label)}"] }
      assert_equal expected, actual, "#{year} breakdown (dot colour, count and name)"
      entries.each { |title, _, n, label| assert_equal "#{n} #{label}", CGI.unescapeHTML(title), "#{year}: tooltip should match the entry" }
    end
  end

  # One row: search, a Type menu, a Research area menu, Clear. The menus are native <details> so the chips
  # take no space until opened; no chip sits outside them.
  def test_type_and_area_chips_sit_in_their_own_menus
    html = html_of("/publications/")
    menus = html.scan(%r{<details class="pub-menu" data-menu="(\w+)">(.*?)</details>}m).to_h
    assert_equal %w[type area], menus.keys, "expected a Type menu then a Research area menu"
    menus.each do |name, body|
      assert_match %r{<summary>[^<]*<span class="pub-menu__count" hidden></span></summary>}, body, "#{name} menu summary needs a hidden count"
      chips = body.scan(/data-filter="(\w+)"/).flatten.uniq
      assert_equal [name], chips, "#{name} menu holds the wrong chips"
    end
    outside = html.gsub(%r{<details class="pub-menu".*?</details>}m, "")
    refute_match(/class="chip"/, outside, "a chip sits outside the menus")
  end

  # Without this rule `.year-controls__all{display:inline-flex}` beats the hidden attribute, so the "hidden
  # until the script runs" Expand all button showed, dead, to visitors without JavaScript (seen in a browser,
  # 2026-11-20). The filter bar, rows and years the script hides rely on it too.
  def test_the_hidden_attribute_beats_component_display_rules
    css = File.read(File.join(BUILD, "assets/css/site.css"))
    assert_match(/\[hidden\]\{display:none!important\}/, css)
  end

  def test_chip_and_filter_bar_are_listed_on_the_design_language_page
    html = html_of("/design-language/")
    %w[.chip .pub-filters .pub-menu .medal .pub-labels .pill].each { |c| assert_has html, "<code>#{c}</code>", "#{c} not listed in Components" }
  end
end

# A paper may sit in several research areas. No paper does in the real data (Kenny decides placements), so this
# builds a throwaway copy of the site with one paper also listed in a second area and checks that its row, its
# pills and /research/ all follow.
class MultiAreaTest < Minitest::Test
  PAPER = "cscw26-peer-supporter" # in `care`; the copy also lists it under `responsible-ai`

  def test_a_paper_in_two_areas_shows_both_pills_and_appears_in_both_sections
    Dir.mktmpdir("cailab-multi-") do |tmp|
      # Real path: on macOS the temp dir is a symlink, and safe mode (github-pages) rejects includes whose
      # real path differs from the site's source path.
      dir = File.realpath(tmp)
      src = File.join(dir, "src")
      FileUtils.mkdir_p(src)
      (Dir.children(ROOT) - %w[vendor .git _site .bundle .playwright-mcp node_modules]).each { |n| FileUtils.cp_r(File.join(ROOT, n), src) }
      path = File.join(src, "_data", "research.yml")
      research = YAML.safe_load(File.read(path))
      research["areas"].find { |a| a["slug"] == "responsible-ai" }["more"] << PAPER
      File.write(path, research.to_yaml)

      out, status = Open3.capture2e({ "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile") },
        "bundle", "exec", "jekyll", "build", "--source", src, "--destination", File.join(dir, "out"), chdir: ROOT)
      assert status.success?, "multi-area build failed:\n#{out}"

      publications = File.read(File.join(dir, "out", "publications", "index.html"))
      row = publications[%r{<li class="publication-row" id="pub-#{PAPER}".*?</li>}m] or flunk("no row for #{PAPER}")
      assert_match(/data-areas="care responsible-ai"/, row, "data-areas should list both areas in research.yml order")
      assert_equal %w[care responsible-ai], row.scan(/class="pill pill--area a\d" data-area="([^"]+)"/).flatten, "one pill per area"

      research_page = File.read(File.join(dir, "out", "research", "index.html"))
      assert_equal 2, research_page.scan(%(href="/publications/#pub-#{PAPER}")).size, "the paper should appear in both sections"
    end
  end
end

# Phone layouts (max-width 640px). A publication row becomes a compact card: its side and main wrappers dissolve
# (display:contents) so venue, figure, title, authors, labels and links sit in one grid, with the thumbnail beside
# the title. On /research/ each area's cards become a swipeable strip. The rendered layout is verified by browser
# measurement, not here (an E2E test needs @playwright/test, a new dependency). What is tested is what that
# layout relies on: the row's structure, a `data-figure` hook, and that both phone rules exist in the phone query.
class PhoneLayoutTest < Minitest::Test
  PUBS = data("publications")

  def rows = html_of("/publications/").scan(%r{<li class="publication-row".*?</li>}m)

  def test_every_row_has_the_structure_the_phone_grid_relies_on
    assert_equal PUBS.size, rows.size
    rows.each_with_index do |row, i|
      at = ->(marker) { row.index(marker) or flunk("row #{i} lacks #{marker}") }
      assert_operator at.('class="publication-row__side"'), :<, at.('class="publication-row__main"')
      assert_operator at.('class="publication-row__main"'), :<, at.('class="publication-row__links"')
      assert_match(%r{<div class="publication-row__side">\s*<p class="publication-row__venue">}, row, "row #{i}: side must start with the venue")
      assert_operator at.('class="publication-row__title"'), :<, at.('class="publication-row__authors"')
      assert_operator at.('class="publication-row__authors"'), :<, at.('class="pub-labels"')
    end
  end

  def test_exactly_the_rows_with_a_figure_carry_data_figure
    rows.zip(PUBS).each do |row, pub|
      tag = row[/<li class="publication-row"[^>]*>/]
      assert_equal !pub["figure"].nil?, tag.match?(/ data-figure(?= |>)/), "data-figure vs figure: #{pub["title"]}"
      assert_equal !pub["figure"].nil?, row.include?('class="publication-row__figure"'), "figure link vs figure: #{pub["title"]}"
    end
  end

  # Everything inside the @media (max-width:640px) blocks of site.css, brace-matched.
  def phone_css
    css = File.read(File.join(BUILD, "assets/css/site.css"))
    css.enum_for(:scan, /@media \(max-width:640px\)\{/).map do
      start = Regexp.last_match.end(0)
      depth = 1
      i = start
      while depth.positive? && i < css.size
        depth += 1 if css[i] == "{"
        depth -= 1 if css[i] == "}"
        i += 1
      end
      css[start...(i - 1)]
    end.join("\n")
  end

  def test_the_phone_query_lays_rows_out_as_a_grid_with_and_without_a_figure
    css = phone_css
    assert_match(/\.publication-row\{[^}]*grid-template-areas/, css, "no phone grid for a plain row")
    assert_match(/\.publication-row\[data-figure\]\{[^}]*grid-template-areas/, css, "no phone grid for a row with a figure")
    assert_match(/\.publication-row__side,\s*\.publication-row__main\{[^}]*display:contents/, css, "side and main must dissolve into the grid")
  end

  def test_the_phone_query_tightens_the_page_header_the_year_summary_and_the_more_links
    css = phone_css
    assert_match(/\.page-header\{[^}]*padding-block/, css, "no compact page header on phones")
    assert_match(/\.page-header h1\{[^}]*font-size/, css, "no smaller page title on phones")
    assert_match(/\.year__type-label\{[^}]*position:absolute/, css, "the year summary's type names must be visually hidden on phones")
    assert_match(/\.paper-link a\{[^}]*display:block/, css, "the More links should flow as text on phones")
    assert_match(/\.paper-link__venue,\s*\.paper-link__title\{[^}]*display:inline/, css, "venue and title should share a line on phones")
  end

  def test_the_phone_query_turns_research_cards_into_a_snapping_strip
    css = phone_css
    assert_match(/\.paper-cards\{[^}]*overflow-x:auto/, css)
    assert_match(/\.paper-cards\{[^}]*scroll-snap-type/, css)
    assert_match(/\.paper-card\{[^}]*scroll-snap-align/, css)
  end
end

# The site is public. Work under review has no public artifact, so requiring one
# keeps it off the site without naming (and so leaking) any title here.
class PublicContentTest < Minitest::Test
  PUBS = data("publications")
  UNDER_SUBMISSION = /under (review|submission)|in submission|submitted to/i

  # `date` is the earliest public availability: YYYY, YYYY-MM or YYYY-MM-DD.
  DATE = /\A\d{4}(-\d\d(-\d\d)?)?\z/

  def test_every_publication_has_a_venue_date_and_public_link
    PUBS.each do |pub|
      assert pub["venue"], "no venue: #{pub["title"]}"
      assert_kind_of String, pub["date"], "no date: #{pub["title"]}"
      assert_match DATE, pub["date"], "bad date format: #{pub["title"]}"
      assert_equal pub["date"][0, 4].to_i, pub["year"], "year disagrees with date: #{pub["title"]}"
      urls = (pub["links"] || []).map { |l| l["url"] }
      assert urls.any? { |u| u.to_s.start_with?("http") }, "no public link: #{pub["title"]}"
    end
  end

  def test_nothing_reads_as_under_submission
    texts = PUBS.flat_map { |p| [p["title"], p["venue"]] } + data("news").map { |n| n["text"] }
    texts.compact.each { |t| refute_match UNDER_SUBMISSION, t, "reads as unpublished: #{t[0, 60]}" }
  end

  # A month-only date sorts after dated entries of that month, a year-only one last in its year.
  def test_publications_are_newest_first
    keys = PUBS.map { |p| "#{p["date"]}-00-00"[0, 10] }
    assert_equal keys.sort.reverse, keys
  end
end

class PeoplePageTest < Minitest::Test
  PEOPLE = data("people")
  LAB = data("lab")

  def test_lists_everyone
    text = text_of("/people/")
    (PEOPLE["members"] + PEOPLE["collaborators"] + left_people)
      .each { |person| assert_has text, person["name"], "missing person: #{person["name"]}" }
  end

  def test_director_is_listed_once_as_director_and_not_among_members
    assert_equal 1, html_of("/people/").scan(/<h3 class="person-card__name">#{Regexp.escape(LAB["director"])}</).size
  end

  # Anyone not in people.yml with a `photo:` must not appear as a photo: consent is per person.
  def test_only_declared_photos_are_used
    srcs = html_of("/people/").scan(/<img[^>]*src="([^"]+)"/).flatten
    allowed = [LAB["director_photo"], "/assets/img/brand/logo-96.png"] + photo_people.map { |p| p["photo"] }
    assert_empty srcs - allowed, "photo without a declaration in people.yml"
  end

  def test_each_declared_photo_renders_once_with_the_persons_name_as_alt
    html = html_of("/people/")
    photo_people.each do |person|
      tags = html.scan(/<img[^>]*alt="#{Regexp.escape(person["name"])}"[^>]*>/)
      assert_equal 1, tags.size, "expected one photo for #{person["name"]}"
      assert_includes tags.first, %(src="#{person["photo"]}"), "wrong file for #{person["name"]}"
    end
  end

  def test_people_without_a_photo_keep_their_initials_or_ring
    html = html_of("/people/")
    members = PEOPLE["members"].reject { |m| m["name"] == LAB["director"] }
    plain_members = members.reject { |m| m["photo"] }
    plain_collabs = PEOPLE["collaborators"].reject { |c| c["photo"] }
    assert_equal plain_members.size, html.scan('class="person-card__initials"').size
    assert_equal plain_collabs.size, html.scan(/<svg class="ring person-card__mini"/).size
    (plain_members + plain_collabs).each do |person|
      refute_match(/<img[^>]*alt="#{Regexp.escape(person["name"])}"/, html, "unexpected photo for #{person["name"]}")
    end
  end

  # Alumni and former collaborators without a photo get a small ring, never an initials disc or nothing.
  def test_people_who_left_without_a_photo_get_a_small_ring
    html = html_of("/people/")
    plain_left = left_people.reject { |p| p["photo"] }
    refute_empty plain_left
    assert_equal plain_left.size, html.scan(/<svg class="ring person-row__ring"/).size
  end

  # Alumni stay folded: no <details> on the page opens by itself.
  def test_every_fold_on_people_starts_closed
    folds = html_of("/people/").scan(/<details[^>]*>/)
    refute_empty folds
    folds.each { |tag| assert_includes tag, 'class="fold"', "unexpected <details>: #{tag}" }
    folds.each { |tag| refute_match(/\bopen\b/, tag, "fold starts open: #{tag}") }
  end

  # Vacuous until someone with a photo moves to alumni or former collaborators; it then pins the rendering:
  # the original file scaled down to 28px, lazy, inside a fold.
  def test_photos_of_people_who_left_are_small_lazy_and_inside_a_fold
    html = html_of("/people/")
    left_people.select { |p| p["photo"] }.each do |person|
      tag = html[/<img[^>]*alt="#{Regexp.escape(person["name"])}"[^>]*>/] or flunk("no photo for #{person["name"]}")
      assert_includes tag, %(src="#{person["photo"]}"), "wrong file for #{person["name"]}"
      %w[class="person-row__photo" width="28" height="28" loading="lazy"].each { |attr| assert_includes tag, attr, "#{person["name"]} photo lacks #{attr}" }
      folds = html.scan(%r{<details class="fold">.*?</details>}m)
      assert folds.any? { |fold| fold.include?(tag) }, "#{person["name"]}'s photo is outside a fold"
    end
  end

  # The "Former collaborators" fold exists exactly when there is someone to list.
  def test_former_collaborators_fold_appears_only_with_entries
    former = PEOPLE["collaborators_former"] || []
    text = text_of("/people/")
    if former.empty?
      refute_has text, "Former collaborators", "empty fold rendered"
    else
      assert_has text, "Former collaborators", "fold missing"
      former.each { |p| assert_has text, p["name"], "former collaborator not listed: #{p["name"]}" }
    end
  end
end

# The row component is documented on /design-language/ with one live specimen of each branch. The director's
# real, already-public photo is used (never a real face under a placeholder name); the ring row is a pure example.
class PersonRowSpecimenTest < Minitest::Test
  def specimen = html_of("/design-language/")

  def test_photo_row_shows_the_directors_photo_scaled_to_28px
    director = data("lab")["director"]
    photo = data("lab")["director_photo"]
    pattern = %r{<img class="person-row__photo" src="#{Regexp.escape(photo)}" width="28" height="28" alt="#{Regexp.escape(director)}"}
    assert pattern.match?(specimen), "no photo specimen with the director's photo and name"
  end

  def test_ring_row_shows_the_fallback
    assert(/<svg class="ring person-row__ring" data-ring="[^"]+"/.match?(specimen), "no ring specimen")
  end

  def test_the_component_is_listed
    assert_has specimen, "<code>.person-row</code>", "person-row not listed in Components"
    assert_has specimen, "<code>.fold</code>", "fold not listed in Components"
  end
end

class ResearchPageTest < Minitest::Test
  RESEARCH = data("research")

  def test_lists_intro_and_every_area_with_its_anchor
    text = plain(text_of("/research/"))
    html = html_of("/research/")
    assert_has text, plain(RESEARCH["intro"])[0, 40], "missing intro"
    RESEARCH["areas"].each do |a|
      assert_has text, a["title"], "missing area #{a["title"]}"
      assert_has text, plain(a["summary"])[0, 40], "missing summary for #{a["title"]}"
      assert_has html, %(id="#{a["slug"]}"), "no section anchor for #{a["title"]}"
    end
  end

  def test_the_umbrella_is_human_centred_ai
    assert_has plain(text_of("/research/")), "Human-Centred AI", "research page lacks the umbrella"
  end

  # The framing text is Kenny's brand. Past talk titles in news.yml are history and are not rewritten.
  def test_no_society_centred_wording_in_the_framing_data
    %w[lab research join].each do |name|
      refute_has File.read(File.join(ROOT, "_data", "#{name}.yml")), "Society-Centred", "old umbrella in #{name}.yml"
    end
  end

  # Press lives on /news/, not under Research.
  def test_media_lives_on_the_news_page_not_research
    research = text_of("/research/")
    news = text_of("/news/")
    refute_has html_of("/research/"), 'id="media"', "media section still on /research/"
    assert_has html_of("/news/"), 'id="media"', "no media section on /news/"
    data("media").each do |m|
      refute_has research, m["title"], "media '#{m["title"]}' still on /research/"
      assert_has news, m["title"], "missing media '#{m["title"]}' on /news/"
    end
  end

  # Funding is hidden on purpose: _data/funding.yml is kept, but nothing renders it.
  def test_funding_is_not_shown_anywhere
    PAGES.each do |page|
      html = html_of(page)
      refute_has html, 'id="funding"', "funding section on #{page}"
      refute_has html, "funding-row", "funding rows on #{page}"
      data("funding").each do |g|
        refute_has text_of(page), g["title"], "grant '#{g["title"]}' shown on #{page}"
        refute_has text_of(page), g["amount"], "grant amount #{g["amount"]} shown on #{page}"
      end
    end
  end
end

# Each research area shows its full papers as thumbnail cards and its other papers as links,
# all opening the paper's row on /publications/.
class ResearchPapersTest < Minitest::Test
  PUBS = data("publications")
  AREAS = data("research")["areas"]
  CARDS = AREAS.flat_map { |a| a["papers"] || [] }
  MORE = AREAS.flat_map { |a| a["more"] || [] }

  def pub(id) = PUBS.select { |p| p["id"] == id }

  def test_every_area_has_cards
    AREAS.each { |a| refute_empty a["papers"].to_a, "area #{a["title"]} has no card papers" }
  end

  def test_every_listed_paper_matches_exactly_one_publication
    (CARDS + MORE).each { |id| assert_equal 1, pub(id).size, "paper id #{id} matches #{pub(id).size} publications" }
  end

  # A paper may sit in several areas (it then shows a pill for each, and appears in each section); it may not
  # be listed twice inside one area. MultiAreaTest builds a site where that happens.
  def test_a_paper_is_listed_once_within_an_area
    AREAS.each do |a|
      all = (a["papers"] || []) + (a["more"] || [])
      assert_equal all.uniq, all, "area #{a["slug"]} lists a paper twice: #{all.select { |i| all.count(i) > 1 }.uniq}"
    end
  end

  def test_area_slugs_are_unique_and_url_safe
    slugs = AREAS.map { |a| a["slug"] }
    assert_equal slugs.uniq, slugs
    slugs.each { |s| assert_match(/\A[a-z0-9-]+\z/, s) }
  end

  def test_publication_ids_are_unique
    ids = PUBS.map { |p| p["id"] }.compact
    assert_equal ids.uniq, ids, "duplicate publication id"
  end

  def test_each_publication_id_anchors_its_row
    html = html_of("/publications/")
    PUBS.map { |p| p["id"] }.compact.each do |id|
      assert_has html, %(<li class="publication-row" id="pub-#{id}"), "no row anchor for #{id}"
    end
  end

  def test_research_page_has_a_card_per_card_paper
    html = html_of("/research/")
    assert_equal CARDS.size, html.scan('<li class="paper-card">').size, "card count"
    CARDS.each do |id|
      paper = pub(id).first
      assert_has html, %(href="/publications/#pub-#{id}"), "no card link for #{id}"
      assert_has html, paper["title"], "no card title for #{id}"
      assert paper["figure"], "card paper #{id} has no figure; a text-only card would unbalance the grid"
      assert_has html, "/assets/img/publications/#{paper["figure"]["slug"]}-thumb.jpg", "no thumbnail for #{id}"
    end
  end

  def test_research_page_has_a_link_per_more_paper
    html = html_of("/research/")
    assert_equal MORE.size, html.scan('<li class="paper-link">').size, "link count"
    MORE.each do |id|
      assert_has html, %(href="/publications/#pub-#{id}"), "no link for #{id}"
      assert_has html, pub(id).first["title"], "no title for #{id}"
    end
  end

  def test_featured_papers_have_a_public_link
    (CARDS + MORE).each { |id| refute_empty pub(id).first["links"], "#{id} has no public link" }
  end
end

class JoinPageTest < Minitest::Test
  VALUES = data("join")["values"]

  def test_lists_values_and_sections
    text = text_of("/join-us/")
    VALUES.each { |v| assert_has text, v["title"], "missing value #{v["title"]}" }
    data("join")["sections"].each { |s| assert_has text, s["title"], "missing section #{s["title"]}" }
  end

  # Each theme gets its own icon, in the same order as the data.
  def test_every_value_has_its_own_icon
    icons = VALUES.map { |v| v["icon"] }
    assert icons.all?, "a value has no icon name"
    assert_equal icons.uniq, icons, "two values share an icon"
    drawn = html_of("/join-us/").scan(/<svg class="icon" data-icon="([^"]+)"/).flatten
    assert_equal icons, drawn
  end

  def test_icons_are_decorative_and_actually_drawn
    svgs = html_of("/join-us/").scan(%r{<svg class="icon".*?</svg>}m)
    assert_equal VALUES.size, svgs.size
    svgs.each do |svg|
      assert_has svg, 'aria-hidden="true"', "icon is exposed to screen readers"
      assert_match(/<(path|circle|rect|polyline|line)\b/, svg, "icon draws nothing: #{svg[0, 60]}")
    end
  end

  def test_lists_every_research_area_and_links_to_it
    html = html_of("/join-us/")
    data("research")["areas"].each do |a|
      assert_has text_of("/join-us/"), a["title"], "join lacks area #{a["title"]}"
      assert_has html, %(href="/research/##{a["slug"]}"), "join topic #{a["title"]} does not open its area"
    end
  end

  def test_scholarship_links_are_kept
    html = html_of("/join-us/")
    assert_has html, "https://www.sutd.edu.sg/Admissions/Graduate/Scholarships", "scholarship link lost"
  end
end

# The "How to apply" section is the lab's intake filter (Kenny's wording, 2026-11-20): a complete package
# per role, a paper response, an AI note and a subject-line format. Everything renders from join.yml, and the
# paper choices come from the research areas, so the list is defined once.
class JoinApplyTest < Minitest::Test
  APPLY = data("join")["apply"]

  def apply_html = html_of("/join-us/")[%r{<section class="section" id="apply">.*?</section>}m] || flunk("no #apply section on /join-us/")

  def apply_text = plain(apply_html.gsub(/<[^>]+>/, " "))

  def test_has_an_apply_section_titled_from_data
    assert_has apply_text, APPLY["title"], "apply section lacks its title"
  end

  def test_lists_every_requirement_for_every_role
    refute_empty APPLY["roles"], "no roles in join.yml apply"
    APPLY["roles"].each do |role|
      assert_has apply_text, role["role"], "apply lacks role #{role["role"]}"
      refute_empty role["items"], "#{role["role"]} has no requirements"
      role["items"].each { |item| assert_has apply_text, plain(item), "#{role["role"]} requirement missing: #{item[0, 50]}" }
    end
  end

  def test_each_role_has_its_subject_line_in_code
    APPLY["roles"].each do |role|
      assert_has plain(apply_html), "<code>#{role["subject"]}</code>", "subject line for #{role["role"]} not shown as code"
    end
    assert_equal APPLY["roles"].size, APPLY["roles"].map { |r| r["subject"] }.uniq.size, "two roles share a subject line"
  end

  # Kenny's rule (2026-11-20): applicants choose among the CHI Honourable Mention papers and the CSCW
  # papers only. The ids live in join.yml `apply.paper.choices`; the venues are read from publications.yml.
  CHOICE_VENUE = /\A(CHI'\d+ · Honourable Mention|PACM HCI \(CSCW'\d+\))\z/

  def test_paper_choices_are_only_chi_honourable_mentions_and_cscw_papers
    ids = APPLY["paper"]["choices"]
    refute_empty ids, "no paper choices in join.yml"
    pubs = data("publications")
    ids.each do |id|
      pub = pubs.find { |p| p["id"] == id } or flunk("choice #{id} is not a publication id")
      assert_match CHOICE_VENUE, pub["venue"], "#{id} (#{pub["venue"]}) is not a CHI Honourable Mention or CSCW paper"
    end
    assert_equal ids.uniq, ids, "a paper is listed twice"
  end

  def test_apply_offers_exactly_the_chosen_papers
    ids = APPLY["paper"]["choices"]
    offered = apply_html.scan(%r{href="/publications/#pub-([^"]+)"}).flatten
    assert_equal ids, offered, "papers offered on the page differ from join.yml apply.paper.choices"
  end

  def test_paper_response_questions_render
    refute_empty APPLY["paper"]["questions"]
    assert_has apply_text, plain(APPLY["paper"]["intro"]), "paper intro missing"
    APPLY["paper"]["questions"].each { |q| assert_has apply_text, plain(q), "paper question missing: #{q[0, 50]}" }
    assert_has apply_text, plain(APPLY["paper"]["close"]), "paper closing line missing"
  end

  def test_ai_note_is_asked_for
    assert_has apply_text, APPLY["ai"]["title"], "AI heading missing"
    assert_has apply_text, plain(APPLY["ai"]["body"]), "AI note text missing"
  end

  def test_asks_applicants_to_strip_identity_numbers_and_states_the_reply_rule
    assert_has apply_text, "NRIC, FIN or passport number", "privacy line about identity numbers missing"
    assert_has apply_text, plain(APPLY["reply_rule"]), "reply rule missing"
  end

  def test_contact_button_sits_in_apply_and_never_prefills_a_subject
    assert_match %r{<a class="btn[^"]*" href="mailto:[^"]*">Contact Us</a>}, apply_html, "no Contact Us button inside #apply"
    hrefs = html_of("/join-us/").scan(/href="(mailto:[^"]*)"/).flatten
    refute_empty hrefs
    hrefs.each { |h| refute_match(/subject=/i, h, "mailto prefills a subject, which defeats the format check") }
  end

  def test_team_closing_points_to_apply
    assert_has html_of("/join-us/"), 'href="#apply"', "closing text does not link to #apply"
    refute_match(/please email Prof/i, text_of("/join-us/"), "old 'just email me' closing still on the page")
  end
end

# The old Google Site had /home, /media and /funding. People have those saved.
class OldUrlRedirectsTest < Minitest::Test
  REDIRECTS = {
    "/home" => "/",
    "/media" => "/news/#media",
    "/funding" => "/research/"
  }.freeze

  # With `url:` set, the plugin writes absolute targets on the production host.
  ORIGIN = "https://#{File.read(File.join(ROOT, "CNAME")).strip}".freeze

  def stub_html(old) = File.read(File.join(BUILD, old, "index.html"))

  def test_each_old_url_has_a_redirect_page_pointing_at_its_new_home
    REDIRECTS.each do |old, target|
      assert File.exist?(File.join(BUILD, old, "index.html")), "no redirect page for #{old}"
      assert_has stub_html(old), %(url=#{ORIGIN}#{target}"), "#{old} does not redirect to #{ORIGIN}#{target}"
    end
  end

  def test_redirect_targets_exist_including_the_section_anchor
    REDIRECTS.each_value do |target|
      page, anchor = target.split("#")
      assert_includes PAGES, page, "#{target} is not a real page"
      assert_has html_of(page), %(id="#{anchor}"), "#{page} has no ##{anchor}" if anchor
    end
  end

  def test_redirect_pages_are_not_linked_from_the_nav
    nav_urls = NAV.map { |n| n["url"] }
    assert_empty REDIRECTS.keys & nav_urls
  end
end

# The production host is named in CNAME (what GitHub Pages serves) and mirrored in _config.yml `url:`.
class ProductionIdentityTest < Minitest::Test
  CNAME_HOST = File.read(File.join(ROOT, "CNAME")).strip
  ORIGIN = "https://#{CNAME_HOST}".freeze

  def meta(page, pattern) = html_of(page)[pattern, 1]

  def test_cname_names_the_production_host_and_is_published
    assert_equal "www.cailab.info", CNAME_HOST
    assert_equal CNAME_HOST, File.read(File.join(BUILD, "CNAME")).strip, "CNAME missing from the built site"
  end

  def test_config_url_matches_the_cname_host
    assert_equal ORIGIN, YAML.safe_load(File.read(File.join(ROOT, "_config.yml")))["url"]
  end

  def test_every_page_has_a_canonical_link_to_its_own_production_url
    PAGES.each do |page|
      assert_equal "#{ORIGIN}#{page}", meta(page, /<link rel="canonical" href="([^"]+)"/), "canonical on #{page}"
    end
  end

  def test_every_page_has_sharing_tags_that_point_at_real_things
    PAGES.each do |page|
      assert_equal "#{ORIGIN}#{page}", meta(page, /property="og:url" content="([^"]+)"/), "og:url on #{page}"
      assert meta(page, /property="og:title" content="([^"]+)"/), "og:title on #{page}"
      assert meta(page, /property="og:description" content="([^"]+)"/), "og:description on #{page}"
      image = meta(page, /property="og:image" content="([^"]+)"/)
      assert image&.start_with?("#{ORIGIN}/"), "og:image on #{page} is not absolute: #{image}"
      assert File.exist?(File.join(BUILD, image.delete_prefix(ORIGIN))), "og:image file missing on #{page}"
    end
  end
end

# A missing favicon logs a 404 on every first visit.
class FaviconTest < Minitest::Test
  def test_root_favicon_exists_and_is_not_empty
    assert File.size?(File.join(BUILD, "favicon.ico")), "favicon.ico missing or empty"
  end

  def test_every_page_links_icons_that_exist
    PAGES.each do |page|
      %w[icon apple-touch-icon].each do |rel|
        href = html_of(page)[/<link rel="#{rel}" href="([^"]+)"/, 1]
        assert href, "#{page} has no #{rel} link"
        assert File.size?(File.join(BUILD, href)), "#{rel} file missing for #{page}: #{href}"
      end
    end
  end
end

# A photo dropped into assets/img was once committed by accident. Only the fixed images and the
# photos declared in people.yml may be published.
class StrayFilesTest < Minitest::Test
  FIXED_IMAGES = %w[brand/logo-480.png brand/logo-96.png brand/apple-touch-icon.png people/kenny-320.jpg].freeze
  ALLOWED_IMAGES = (FIXED_IMAGES + photo_people.map { |p| p["photo"].delete_prefix("/assets/img/") } + publication_images + gallery_images).freeze

  def test_assets_img_holds_only_the_expected_files_in_source
    img = File.join(ROOT, "assets", "img")
    found = Dir.glob("**/*", base: img).select { |f| File.file?(File.join(img, f)) }.sort
    assert_equal ALLOWED_IMAGES.sort, found, "unexpected file(s) in assets/img"
  end

  def test_no_other_image_is_published
    images = Dir.glob(File.join(BUILD, "**", "*.{png,jpg,jpeg,gif,webp,svg}")).map { |f| f.sub("#{BUILD}/assets/img/", "") }
    assert_empty images - ALLOWED_IMAGES, "unexpected image(s) in the published site"
  end
end

# Camera or editor metadata (EXIF/XMP, IPTC, comments) can carry a location or a name. `sips` writes an
# EXIF segment into every JPEG it saves, so bin/figure strips it; this proves nothing slipped through.
class ImageMetadataTest < Minitest::Test
  APP1_EXIF_XMP = 0xE1
  APP13_IPTC = 0xED
  COMMENT = 0xFE

  def test_no_jpeg_carries_metadata
    Dir.glob(File.join(ROOT, "assets", "img", "**", "*.jpg")).each do |path|
      found = jpeg_segments(path).map(&:first) & [APP1_EXIF_XMP, APP13_IPTC, COMMENT]
      assert_empty found, "metadata segment(s) #{found.map { |m| format("0x%X", m) }.join(", ")} in #{path.sub("#{ROOT}/", "")}"
    end
  end
end

# The thumbnail is a plain link to the large image, so it still works without JavaScript.
class PublicationFigureTest < Minitest::Test
  PUBS = data("publications")
  IMG = File.join(ROOT, "assets", "img", "publications")

  def rows = html_of("/publications/").scan(%r{<li class="publication-row"[^>]*>.*?</li>}m)

  def test_figures_are_declared
    refute_empty figure_pubs, "no publication declares a figure, so the figure tests below check nothing"
  end

  def test_each_figure_has_a_slug_alt_text_and_both_files
    figure_pubs.each do |pub|
      fig = pub["figure"]
      assert_match(/\A[a-z0-9-]+\z/, fig["slug"].to_s, "bad figure slug: #{pub["title"]}")
      assert fig["alt"].to_s.strip.size > 20, "figure needs alt text describing what it shows: #{pub["title"]}"
      refute_equal pub["title"], fig["alt"], "alt text must describe the figure, not repeat the title"
      large = File.join(IMG, "#{fig["slug"]}.jpg")
      thumb = File.join(IMG, "#{fig["slug"]}-thumb.jpg")
      assert File.size?(large), "missing #{File.basename(large)}"
      assert File.size?(thumb), "missing #{File.basename(thumb)}"
      assert_operator jpeg_size(thumb)[0], :<=, 600, "thumbnail too wide: #{File.basename(thumb)}"
      assert_operator jpeg_size(large)[0], :<=, 2000, "large image too wide: #{File.basename(large)}"
      assert_operator jpeg_size(large)[0], :>, jpeg_size(thumb)[0], "large image is not larger than its thumbnail"
    end
  end

  def test_figure_slugs_are_unique
    slugs = figure_pubs.map { |p| p["figure"]["slug"] }
    assert_equal slugs.uniq, slugs
  end

  def test_each_thumbnail_links_to_its_large_image
    figure_pubs.each do |pub|
      slug = pub["figure"]["slug"]
      alt = CGI.escapeHTML(pub["figure"]["alt"])
      row = rows.find { |r| r.include?(pub["title"]) }
      assert row, "no row for #{pub["title"]}"
      assert_match %r{<a class="publication-row__figure" href="[^"]*/assets/img/publications/#{slug}\.jpg"}, row
      assert_match %r{<img src="[^"]*/assets/img/publications/#{slug}-thumb\.jpg" alt="#{Regexp.escape(alt)}"}, row
      assert_match(/<img [^>]*width="\d+" height="\d+" loading="lazy"/, row, "thumbnail needs width, height and lazy loading")
    end
  end

  def test_rows_without_a_figure_render_no_image
    assert_equal figure_pubs.size, rows.count { |r| r.include?("<img") }
    assert_equal figure_pubs.size, rows.count { |r| r.include?("publication-row__figure") }
  end
end

# Nothing from YouTube loads until a visitor presses play, so no page carries an iframe in its HTML
# and the script only ever builds a privacy-enhanced (youtube-nocookie.com) embed.
class PublicationVideoTest < Minitest::Test
  IMG = File.join(ROOT, "assets", "img", "publications")

  def test_each_video_has_an_id_title_and_a_16_by_9_poster
    video_pubs.each do |pub|
      video = pub["video"]
      assert_match(/\A[\w-]{11}\z/, video["youtube"].to_s, "not a YouTube id: #{pub["title"]}")
      assert_match(/\A[a-z0-9-]+\z/, video["slug"].to_s, "bad video slug: #{pub["title"]}")
      assert video["title"].to_s.strip.size > 5, "video needs a title: #{pub["title"]}"
      poster = File.join(IMG, "#{video["slug"]}-poster.jpg")
      assert File.size?(poster), "missing #{File.basename(poster)}"
      width, height = jpeg_size(poster)
      assert_in_delta 16.0 / 9, width.to_f / height, 0.05, "poster must be 16:9 or the dialog jumps when the player loads"
    end
  end

  def test_each_video_button_links_to_youtube_without_javascript
    video_pubs.each do |pub|
      id = pub["video"]["youtube"]
      html = html_of("/publications/")
      assert_has html, %(href="https://www.youtube.com/watch?v=#{id}" data-video="#{id}"), "no Video button for #{pub["title"]}"
    end
  end

  def test_no_page_has_an_iframe_in_its_html
    Dir.glob(File.join(BUILD, "**", "*.html")).each do |file|
      refute_match(/<iframe/i, File.read(file), "#{file.delete_prefix(BUILD)} embeds an iframe on load")
    end
  end

  def test_script_embeds_only_the_privacy_enhanced_domain
    js = File.read(File.join(ROOT, "assets", "js", "figure.js"))
    assert_has js, "youtube-nocookie.com/embed/", "figure.js must embed from youtube-nocookie.com"
    refute_match %r{(?<!-nocookie)youtube\.com/embed}, js, "figure.js embeds from the tracking domain"
  end
end

# Moving someone between lists is easy to half-do. These guard the data, not the pages.
class PeopleDataTest < Minitest::Test
  PEOPLE = data("people")

  # `collaborators_former` is absent from people.yml until someone becomes a former collaborator.
  def names(key) = (PEOPLE[key] || []).map { |p| p["name"] }

  def test_nobody_is_listed_twice_anywhere
    all = PEOPLE.keys.flat_map { |key| names(key) }
    dupes = all.group_by(&:itself).select { |_, v| v.size > 1 }.keys
    assert_empty dupes, "listed more than once: #{dupes.join(', ')}"
  end

  def test_current_members_are_not_also_alumni
    current = names("members") + names("collaborators")
    gone = names("alumni_graduate") + names("alumni_undergraduate") + names("collaborators_former")
    assert_empty current & gone, "both current and alumni or former collaborator: #{(current & gone).join(', ')}"
  end

  # The alumni list is newest-first and every graduate has a year.
  def test_graduate_alumni_have_years_and_run_newest_first
    years = PEOPLE["alumni_graduate"].map do |p|
      year = p["note"][/Graduated (\d{4})/, 1]
      assert year, "#{p["name"]} has no graduation year"
      year.to_i
    end
    assert_equal years.sort.reverse, years, "graduate alumni are not newest-first: #{years.inspect}"
  end

  def test_the_director_is_a_member
    assert_includes names("members"), data("lab")["director"]
  end

  def test_every_declared_photo_file_exists_and_is_a_jpeg_under_assets_img
    photo_people.each do |person|
      assert_match %r{\A/assets/img/people/[\w-]+\.jpg\z}, person["photo"], "bad photo path for #{person["name"]}"
      assert File.size?(File.join(ROOT, person["photo"])), "missing photo file for #{person["name"]}"
    end
  end

  def test_the_directors_photo_file_exists
    path = data("lab")["director_photo"]
    assert_match %r{\A/assets/img/people/[\w-]+\.jpg\z}, path
    assert File.size?(File.join(ROOT, path)), "missing director photo: #{path}"
  end

  def test_every_entry_has_a_name_and_a_role_or_note
    PEOPLE["members"].each { |p| assert p["role"].to_s.strip != "", "#{p["name"]} has no role" }
    (PEOPLE["collaborators"] + (PEOPLE["collaborators_former"] || [])).each { |p| assert p["role"].to_s.strip != "", "#{p["name"]} has no role" }
    (PEOPLE["alumni_graduate"] + PEOPLE["alumni_undergraduate"]).each { |p| assert p["note"].to_s.strip != "", "#{p["name"]} has no note" }
  end
end

# The Gallery: albums of photos by event. Until the first album exists the page is unpublished (`published: false`
# in gallery.html) and has no nav entry; nothing else is hidden by a switch. Everything is tested twice: the rules
# on gallery.yml as a pure function (so they are proved on bad data too, with no photo needed), and the rendering on
# the specimen album that /design-language/ draws from publication figures.
module GalleryRules
  SLUG = /\A[a-z0-9-]+\z/
  DATE = /\A\d{4}(-\d{2}(-\d{2})?)?\z/
  ISO_DAY = /\A\d{4}-\d{2}-\d{2}\z/

  def self.valid_date?(str)
    return false unless str.is_a?(String) && str.match?(DATE)
    year, month, day = str.split("-").map(&:to_i)
    Date.valid_date?(year, month || 1, day || 1)
  end

  # Newest first. A missing month or day counts as 00, the start of its period, so the order here is exactly the
  # order of the YYYYMMDD names (slug_prefix) that the page sorts by and Finder lists.
  def self.sort_key(str)
    year, month, day = str.split("-").map(&:to_i)
    [year, month || 0, day || 0]
  end

  # "2026-07-02" -> "20260702", "2026-07" -> "20260700", "2026" -> "20260000": what an album's slug must start with.
  def self.slug_prefix(str) = format("%04d%02d%02d", *sort_key(str))

  # Problems with the data alone (no files): an empty list means the albums are fit to publish.
  def self.problems(albums, categories, today: Date.today)
    found = []
    slugs = albums.map { |a| a["slug"] }
    found << "duplicate album slug(s): #{slugs.select { |s| slugs.count(s) > 1 }.uniq.join(", ")}" if slugs.uniq.size != slugs.size
    # Undated albums (undated: true) sit outside the order: only dated ones are checked for newest first.
    dated = albums.select { |a| a["undated"] != true && valid_date?(a["date"]) }
    keys = dated.map { |a| sort_key(a["date"]) }
    found << "albums are not newest first" unless keys == keys.sort.reverse
    albums.each do |a|
      name = a["slug"].inspect
      found << "#{name}: slug must be lowercase letters, digits and hyphens" unless a["slug"].to_s.match?(SLUG)
      if a["undated"] == true
        found << "#{name}: an undated album must not have a date" if a.key?("date")
        found << "#{name}: an undated album's slug must not start with a date (eight digits)" if a["slug"].to_s.match?(/\A\d{8}/)
      else
        found << "#{name}: undated must be true (or left out)" if a.key?("undated")
        if valid_date?(a["date"]) && !a["slug"].to_s.match?(/\A#{slug_prefix(a["date"])}-[a-z0-9]/)
          found << "#{name}: slug must start with #{slug_prefix(a["date"])}- (the date as YYYYMMDD, 00 for a missing month or day), then a name"
        end
      end
      found << "#{name}: needs a title" if a["title"].to_s.strip.empty?
      found << "#{name}: date must be a quoted YYYY, YYYY-MM or YYYY-MM-DD (or the album is undated: true)" unless a["undated"] == true || valid_date?(a["date"])
      found << "#{name}: category #{a["category"].inspect} is not in categories" unless categories.include?(a["category"])
      consent = a["consent"]
      if !consent.is_a?(String) || !consent.match?(ISO_DAY) || !valid_date?(consent)
        found << "#{name}: consent must be the quoted YYYY-MM-DD the people shown agreed to web use"
      elsif Date.parse(consent) > today
        found << "#{name}: consent is dated in the future"
      end
      found << "#{name}: link must be a path on this site" if a["link"] && !a["link"].to_s.start_with?("/")
      photos = a["photos"] || []
      found << "#{name}: has no photos" if photos.empty?
      found << "#{name}: the same photo file is listed twice" if photos.map { |p| p["file"] }.uniq.size != photos.size
      photos.each do |p|
        # Quoted: an unquoted 01 is the number 1 in YAML. The images are assets/img/gallery/<album>/<file>.jpg.
        found << "#{name}: file #{p["file"].inspect} must be a quoted number such as \"01\"" unless p["file"].is_a?(String) && p["file"].match?(/\A\d{2,}\z/)
        found << "#{name}: #{p["file"]}: alt text must say what the photo shows (more than 20 characters)" unless p["alt"].to_s.strip.size > 20
        found << "#{name}: #{p["file"]}: alt text repeats the album title" if p["alt"].to_s.strip == a["title"].to_s.strip
        found << "#{name}: #{p["file"]}: width and height must be whole pixels" unless [p["width"], p["height"]].all? { |n| n.is_a?(Integer) && n > 0 }
      end
    end
    found
  end

  # Problems with the image files of the given albums: img_dir is assets/img, where each album has gallery/<slug>/.
  def self.file_problems(albums, img_dir)
    albums.flat_map { |a| a["photos"].flat_map { |p| photo_file_problems(p, File.join(img_dir, "gallery", a["slug"])) } }
  end

  def self.photo_file_problems(photo, dir)
    large = File.join(dir, "#{photo["file"]}.jpg")
    thumb = File.join(dir, "#{photo["file"]}-thumb.jpg")
    return ["missing #{File.basename(large)}"] unless File.size?(large)
    return ["missing #{File.basename(thumb)}"] unless File.size?(thumb)
    found = []
    (w, h), (tw, th) = jpeg_size(large), jpeg_size(thumb)
    found << "#{File.basename(large)} is #{w}x#{h}, declared #{photo["width"]}x#{photo["height"]}" unless [w, h] == [photo["width"], photo["height"]]
    # The size rule: no full-resolution photos. A lightbox photo is never shown more than ~720px tall, so the long
    # edge is capped at 1280 and the file at 350 KB; the thumbnail fits 640x480 and 120 KB. bin/figure photo makes this.
    found << "#{File.basename(large)}: long edge is over 1280px (run it through bin/figure photo)" if [w, h].max > 1280
    found << "#{File.basename(large)}: #{File.size(large) / 1000} KB is over the 350 KB cap" if File.size(large) > 350_000
    found << "#{File.basename(thumb)}: thumbnail is over 640x480" if tw > 640 || th > 480
    found << "#{File.basename(thumb)}: thumbnail #{File.size(thumb) / 1000} KB is over the 120 KB cap" if File.size(thumb) > 120_000
    found << "#{File.basename(thumb)}: thumbnail is not smaller than its photo" unless tw < w || th < h
    found << "#{File.basename(thumb)}: thumbnail is not the photo's shape" unless (tw.to_f / th - w.to_f / h).abs < 0.03 * (w.to_f / h)
    found
  end
end

class GalleryVisibilityTest < Minitest::Test
  def test_the_page_and_its_nav_entry_exist_exactly_when_there_is_an_album
    has_albums = !gallery_albums.empty?
    assert_equal has_albums, File.exist?(File.join(BUILD, "gallery", "index.html")),
      "/gallery/ must be built exactly when gallery.yml has an album (gallery.html carries `published: false` until then)"
    assert_equal has_albums, NAV.any? { |n| n["url"] == "/gallery/" },
      "nav.yml lists Gallery exactly when gallery.yml has an album"
  end

  def test_gallery_sits_immediately_before_code_in_the_nav
    skip "no album yet, so Gallery is not in the nav" if gallery_albums.empty?
    urls = NAV.map { |n| n["url"] }
    assert_equal "/gallery/", urls[-2], "Gallery goes just before Code"
    assert NAV.last["external"], "the last nav entry is the external Code link"
  end

  def test_every_page_links_to_gallery_only_when_it_is_published
    PAGES.each do |page|
      assert_equal !gallery_albums.empty?, html_of(page).include?('href="/gallery/"'), "gallery link on #{page}"
    end
  end
end

class GalleryDataTest < Minitest::Test
  CATEGORIES = data("gallery")["categories"].map { |c| c["id"] }

  def test_categories_have_unique_ids_and_labels
    cats = data("gallery")["categories"]
    assert_equal cats.size, cats.map { |c| c["id"] }.uniq.size
    cats.each do |c|
      assert_match GalleryRules::SLUG, c["id"].to_s
      refute_empty c["label"].to_s.strip
    end
  end

  def test_the_albums_obey_the_rules
    skip "gallery.yml has no albums yet; the rules are proved on bad data below" if gallery_albums.empty?
    assert_empty GalleryRules.problems(gallery_albums, CATEGORIES)
  end

  def test_every_photo_file_exists_with_the_declared_size
    skip "gallery.yml has no albums yet" if gallery_albums.empty?
    assert_empty GalleryRules.file_problems(gallery_albums, File.join(ROOT, "assets", "img"))
  end

  GOOD = {
    "slug" => "20260400-chi26", "title" => "CHI 2026", "date" => "2026-04", "category" => "conferences", "consent" => "2026-05-01",
    "photos" => [{"file" => "01", "alt" => "The lab's poster stand at the conference hall", "width" => 800, "height" => 600}]
  }.freeze

  def problems(**changes) = GalleryRules.problems([GOOD.merge(changes.transform_keys(&:to_s))], CATEGORIES, today: Date.new(2026, 11, 20))

  def test_the_rules_accept_a_good_album
    assert_empty problems
  end

  def test_an_album_without_consent_is_refused_and_so_is_a_vague_or_future_one
    assert_match(/consent/, problems(consent: nil).join)
    assert_match(/consent/, problems(consent: "yes").join)
    assert_match(/consent/, problems(consent: "2026-13-40").join)
    assert_match(/future/, problems(consent: "2027-01-01").join)
  end

  def test_the_rules_catch_the_other_mistakes
    assert_match(/category/, problems(category: "parties").join)
    assert_match(/slug/, problems(slug: "Bad Slug").join)
    assert_match(/date/, problems(date: "April 2026").join)
    assert_match(/no photos/, problems(photos: []).join)
    assert_match(/quoted number/, problems(photos: [GOOD["photos"][0].merge("file" => "photo-1")]).join)
    assert_match(/quoted number/, problems(photos: [GOOD["photos"][0].merge("file" => 1)]).join, "an unquoted 01 is an Integer")
    assert_match(/listed twice/, problems(photos: [GOOD["photos"][0], GOOD["photos"][0]]).join)
    assert_match(/alt text/, problems(photos: [GOOD["photos"][0].merge("alt" => "photo")]).join)
    long = "Photographs from the CHI 2026 conference in Barcelona"
    assert_match(/repeats the album title/, problems(title: long, photos: [GOOD["photos"][0].merge("alt" => long)]).join)
    assert_match(/link/, problems(link: "https://example.org").join)
  end

  def test_the_rules_catch_duplicates_and_wrong_order
    a = GOOD
    b = GOOD.merge("slug" => "20260600-dis26", "date" => "2026-06")
    assert_match(/not newest first/, GalleryRules.problems([a, b], CATEGORIES).join)
    assert_empty GalleryRules.problems([b, a], CATEGORIES, today: Date.new(2026, 11, 20))
    assert_match(/duplicate album slug/, GalleryRules.problems([a, a], CATEGORIES).join)
  end

  # The folder name is the sort key: assets/img/gallery/<YYYYMMDD-name>/ lists in date order in Finder, and the page
  # orders albums by the same name. A missing month or day is 00, so a month-only album sorts as the start of its month.
  def test_a_month_only_date_sorts_as_the_start_of_its_month
    a = GOOD.merge("date" => "2026-04")
    b = GOOD.merge("slug" => "20260420-dis26", "date" => "2026-04-20")
    assert_empty GalleryRules.problems([b, a], CATEGORIES, today: Date.new(2026, 11, 20))
    assert_match(/not newest first/, GalleryRules.problems([a, b], CATEGORIES, today: Date.new(2026, 11, 20)).join)
  end

  def test_the_slug_starts_with_the_albums_date_as_yyyymmdd
    assert_equal "20260702", GalleryRules.slug_prefix("2026-07-02")
    assert_equal "20260700", GalleryRules.slug_prefix("2026-07")
    assert_equal "20260000", GalleryRules.slug_prefix("2026")
    assert_match(/must start with 20260400-/, problems(slug: "chi26").join, "no date in the name")
    assert_match(/must start with 20260400-/, problems(slug: "20260401-chi26").join, "the wrong day")
    assert_match(/must start with 20260400-/, problems(slug: "202604-chi26").join, "six digits are not YYYYMMDD")
    assert_match(/must start with 20260400-/, problems(slug: "20260400").join, "a date and nothing after it")
    assert_empty problems(slug: "20260400-chi-2026-poster-stand")
    assert_empty problems(date: "2026-04-20", slug: "20260420-chi26")
    assert_empty problems(date: "2026", slug: "20260000-chi26")
  end

  # An album tied to no year (the catch-all, "Outtakes & Oddities") says so explicitly, with undated: true. Without a
  # date and without the flag it is an error, so a typo'd or forgotten date never turns an album into a catch-all by
  # accident. Its slug has no date prefix, and must not look like one.
  UNDATED = GOOD.reject { |k, _| k == "date" }.merge("slug" => "outtakes-and-oddities", "undated" => true).freeze

  def undated_problems(**changes) = GalleryRules.problems([UNDATED.merge(changes.transform_keys(&:to_s))], CATEGORIES, today: Date.new(2026, 11, 20))

  def test_an_undated_album_has_the_flag_no_date_and_a_plain_slug
    assert_empty undated_problems
    assert_empty undated_problems(slug: "odds-1")
  end

  def test_an_undated_album_must_not_carry_a_date_or_a_dated_slug
    assert_match(/must not have a date/, undated_problems(date: "2026-04").join)
    assert_match(/must not start with a date/, undated_problems(slug: "20260400-outtakes").join)
    assert_match(/must not start with a date/, undated_problems(slug: "20240000-outtakes").join)
  end

  def test_a_missing_date_without_the_flag_is_an_error_and_so_is_a_flag_that_is_not_true
    assert_match(/date must be a quoted/, problems(date: nil).join, "a forgotten date is not a catch-all")
    assert_match(/date must be a quoted/, GalleryRules.problems([GOOD.reject { |k, _| k == "date" }], CATEGORIES, today: Date.new(2026, 11, 20)).join)
    assert_match(/undated must be true/, problems(undated: false).join)
    assert_match(/undated must be true/, undated_problems(undated: "yes").join)
  end

  def test_undated_albums_sit_outside_the_newest_first_order_and_still_need_the_rest
    today = Date.new(2026, 11, 20)
    a = GOOD
    b = GOOD.merge("slug" => "20260600-dis26", "date" => "2026-06")
    assert_empty GalleryRules.problems([UNDATED, b, a], CATEGORIES, today: today), "an undated album may sit anywhere in the file"
    assert_empty GalleryRules.problems([b, UNDATED, a], CATEGORIES, today: today)
    assert_match(/not newest first/, GalleryRules.problems([a, UNDATED, b], CATEGORIES, today: today).join, "the dated ones are still checked")
    assert_match(/consent/, undated_problems(consent: nil).join)
    assert_match(/no photos/, undated_problems(photos: []).join)
    assert_match(/duplicate album slug/, GalleryRules.problems([UNDATED, UNDATED], CATEGORIES, today: today).join)
  end

  def test_file_rules_catch_missing_oversize_and_misdeclared_images
    Dir.mktmpdir do |dir|
      img = File.join(ROOT, "assets", "img")
      FileUtils.cp(File.join(img, "publications", "pg25-vr-modeling.jpg"), File.join(dir, "01.jpg")) # 1600x298
      photo = {"file" => "01", "width" => 1600, "height" => 298}
      assert_match(/missing 01-thumb\.jpg/, GalleryRules.photo_file_problems(photo, dir).join)
      FileUtils.cp(File.join(img, "publications", "eacl26-blend-vis-thumb.jpg"), File.join(dir, "01-thumb.jpg")) # 480x300: the wrong shape for a 1600x298 photo
      assert_match(/not the photo's shape/, GalleryRules.photo_file_problems(photo, dir).join)
      assert_match(/long edge is over 1280px/, GalleryRules.photo_file_problems(photo, dir).join, "no full-resolution photos")
      assert_match(/declared 1000x298/, GalleryRules.photo_file_problems(photo.merge("width" => 1000), dir).join)
      assert_match(/missing 99\.jpg/, GalleryRules.photo_file_problems({"file" => "99"}, dir).join)
    end
  end
end

# The specimen albums on /design-language/: the same includes the real page uses (gallery-index, gallery-album), fed
# publication figures already on the site, so the cards, the chips, the year headings and the lightbox are tested
# on real markup before the lab has many albums of its own.
class GallerySpecimenTest < Minitest::Test
  ALBUMS = data("gallery_specimen")["albums"]
  CATEGORIES = data("gallery")["categories"]
  IMG = File.join(ROOT, "assets", "img", "publications")

  def page = html_of("/design-language/")
  def card(slug) = page[%r{<details class="album" id="album-#{slug}".*?</details>}m]
  def tiles(html) = html.scan(%r{<li class="album__photo".*?</li>}m)
  def album(slug) = ALBUMS.find { |a| a["slug"] == slug }

  def test_the_specimen_has_seven_albums_five_in_2026_one_in_2025_and_one_tied_to_no_year
    assert_equal 7, ALBUMS.size
    dated = ALBUMS.reject { |a| a["undated"] }
    assert_equal %w[2025 2026], dated.map { |a| a["date"][0, 4] }.uniq.sort
    assert_equal 5, dated.count { |a| a["date"].start_with?("2026") }, "enough cards to overflow a strip at desktop width"
    assert_equal 1, ALBUMS.count { |a| a["undated"] }
    assert_nil ALBUMS.find { |a| a["undated"] }["date"], "an undated album has no date"
    assert_equal 4, ALBUMS.map { |a| a["category"] }.uniq.size
    assert_equal [14, 2, 1, 2, 3, 1, 2], ALBUMS.map { |a| a["photos"].size }, "a big album, small ones and single photos"
  end

  def test_the_specimen_photos_have_alt_text_sizes_and_files
    ALBUMS.flat_map { |a| a["photos"] }.each do |p|
      assert p["alt"].to_s.strip.size > 20, "alt text for #{p["file"]}"
      assert File.size?(File.join(IMG, "#{p["file"]}.jpg")), "missing #{p["file"]}.jpg"
      assert File.size?(File.join(IMG, "#{p["file"]}-thumb.jpg")), "missing #{p["file"]}-thumb.jpg"
      assert_equal [p["width"], p["height"]], jpeg_size(File.join(IMG, "#{p["file"]}.jpg")), "declared size of #{p["file"]}"
    end
  end

  def ids_in(html) = html.scan(/<details class="album" id="album-([^"]+)"/).flatten

  def test_each_album_is_a_card_in_its_year_newest_first_and_the_undated_one_comes_last_under_anytime
    years = page.scan(/<h2 class="gallery-year__title"[^>]*>(\d{4})<\/h2>/).flatten
    assert_equal %w[2026 2025], years
    sections = page.scan(%r{<section class="gallery-year" .*?</section>}m)
    assert_equal %w[20261100-specimen-demos 20261000-specimen-long 20260912-specimen-short 20260800-specimen-no-place 20260600-specimen-conferences], ids_in(sections[0])
    assert_equal %w[20250900-specimen-single], ids_in(sections[1])
    undated = page[%r{<section class="gallery-year gallery-year--undated".*?</section>}m]
    refute_nil undated, "no undated section"
    assert_equal %w[specimen-undated], ids_in(undated)
    assert_match(%r{<h2 class="gallery-year__title" id="gallery-undated">Anytime</h2>}, undated)
    assert_operator page.index("gallery-year--undated"), :>, page.index('id="gallery-2025"'), "after every year"
    [*sections, undated].each { |sec| assert_match(/<div class="album-cards">/, sec) }
  end

  def test_an_undated_card_has_no_date_and_no_year
    c = card("specimen-undated")
    refute_nil c
    refute_match(/<time/, c, "no date, so no <time>")
    assert_match(%r{<span class="album__meta">2 photos</span>}, c)
    assert_match(/data-category="lab-life"/, c)
  end

  def test_every_strip_has_two_arrows_that_start_hidden_for_gallery_carousel_js
    assert_equal 3, page.scan('<div class="album-carousel">').size, "two years and the undated section"
    prevs = page.scan(%r{<button class="album-carousel__btn album-carousel__prev" type="button" aria-label="Scroll albums left" aria-disabled="true" hidden>})
    nexts = page.scan(%r{<button class="album-carousel__btn album-carousel__next" type="button" aria-label="Scroll albums right" aria-disabled="false" hidden>})
    assert_equal [3, 3], [prevs.size, nexts.size]
  end

  def test_a_card_is_a_summary_with_the_first_photo_as_cover_a_title_and_the_facts
    c = card("20261100-specimen-demos")
    refute_nil c
    first = album("20261100-specimen-demos")["photos"][0]
    assert_match(%r{<summary class="album__card" aria-haspopup="dialog">}, c, "the card announces that it opens a dialog")
    assert_match(%r{<img class="album__cover" src="/assets/img/publications/#{first["file"]}-thumb\.jpg" width="#{first["width"]}" height="#{first["height"]}" alt="" loading="lazy">}, c)
    assert_match(%r{<h3 class="album__title">Specimen album</h3>}, c)
    assert_match(%r{<time datetime="2026-11">November 2026</time> · Singapore · 14 photos}, c)
    assert_match(/data-category="demos"/, c)
    assert_match(%r{· 1 photo</span>}, card("20250900-specimen-single"), "singular for one photo")
    assert_match(%r{<time datetime="2026-06">June 2026</time> · 3 photos}, card("20260600-specimen-conferences"), "no place when there is none")
  end

  def test_the_card_body_lists_every_photo_as_a_plain_link_without_an_inner_fold
    refute_includes page, "album__rest", "the card is the disclosure; there is no second fold"
    ALBUMS.each do |a|
      body = card(a["slug"])[%r{<div class="album__body">.*}m]
      assert_equal a["photos"].size, tiles(body).size, a["slug"]
      tiles(body).zip(a["photos"]).each do |tile, p|
        ratio = (p["width"].to_f / p["height"]).round(3)
        assert_match(/style="--ar:#{ratio}"/, tile, "aspect ratio of #{p["file"]}")
        assert_match %r{<a href="/assets/img/publications/#{p["file"]}\.jpg" data-figure data-group="album-#{a["slug"]}" data-title="#{Regexp.escape(CGI.escapeHTML(a["title"]))}" data-alt="}, tile
        assert_match %r{<img src="/assets/img/publications/#{p["file"]}-thumb\.jpg" width="#{p["width"]}" height="#{p["height"]}" alt="[^"]{20,}" loading="lazy">}, tile
      end
    end
  end

  def test_the_summary_and_a_caption_and_a_credit_travel_with_the_markup
    assert_match(/class="album__summary"/, card("20261100-specimen-demos"))
    refute_match(/album__summary/, card("20250900-specimen-single"), "no summary, no empty block")
    photos = album("20261100-specimen-demos")["photos"]
    cap = photos.index { |p| p["caption"] }
    refute_nil cap
    tile = tiles(card("20261100-specimen-demos"))
    assert_includes tile[cap], %(data-caption="#{CGI.escapeHTML(photos[cap]["caption"])}")
    cred = photos.index { |p| p["credit"] }
    refute_nil cred
    assert_includes tile[cred], 'data-credit="CAILab"'
    plain = tile.reject.with_index { |_, i| [cap, cred].include?(i) }.first
    refute_includes plain, "data-caption"
    refute_includes plain, "data-credit"
  end

  def test_chips_cover_the_four_categories_in_use_with_counts_and_start_hidden
    assert_match(/<div class="gallery-filters" hidden>/, page, "revealed by gallery-filter.js")
    chips = page.scan(%r{data-filter="category" data-value="([^"]+)">([^<]+) <span class="chip__count">(\d+)</span>})
    assert_equal [%w[conferences Conferences 1], %w[lab-life Lab\ life 3], %w[outreach Outreach 1], %w[demos Demos 2]], chips.map { |v, l, n| [v, l, n] }
  end

  def test_the_lightbox_has_steps_a_counter_all_photos_and_its_scripts_here_and_on_publications
    ["/design-language/", "/publications/"].each do |path|
      html = html_of(path)
      assert_match(/<dialog class="figure-dialog" id="figure-dialog"/, html, path)
      assert_match(/<div class="figure-dialog__nav" hidden>/, html, "the nav starts hidden on #{path}; figure.js shows it for a group")
      assert_match(/<button class="figure-dialog__all" type="button" hidden>All photos<\/button>/, html, path)
      assert_match(/figure-dialog__prev" type="button" aria-label="Previous photo"/, html, path)
      assert_match(/figure-dialog__next" type="button" aria-label="Next photo"/, html, path)
      assert_match(/figure-dialog__count" aria-live="polite"/, html, path)
      assert_has html, 'src="/assets/js/figure.js"', "figure.js on #{path}"
    end
  end

  def test_the_carousel_script_loads_here_and_before_the_filter_and_the_lightbox
    html = page
    assert_has html, 'src="/assets/js/gallery-carousel.js"', "gallery-carousel.js"
    assert_operator html.index('src="/assets/js/gallery-carousel.js"'), :<, html.index('src="/assets/js/gallery-filter.js"')
  end

  def test_the_filter_script_loads_before_the_lightbox_script
    html = page
    assert_operator html.index('src="/assets/js/gallery-filter.js"'), :<, html.index('src="/assets/js/figure.js"'),
      "a link to an album the filter hides must clear the filter before figure.js opens the album"
  end

  def test_publication_thumbnails_stay_ungrouped
    refute_includes html_of("/publications/"), "data-group", "a publication figure opens alone"
  end

  def test_the_components_are_listed_on_the_design_language_page
    %w[.album .album-carousel .album__card .album__grid .figure-dialog].each { |c| assert_has page, "<code>#{c}</code>", "#{c} is not listed" }
    assert_match(/Gallery photos\./, page)
  end

  def test_the_specimen_is_never_listed_on_other_pages
    (PAGES - ["/design-language/"]).each { |path| refute_includes html_of(path), "album-specimen", path }
  end
end

# Once the first album exists these hold for the real page. They skip while there is no album (the page is not built).
class GalleryPageTest < Minitest::Test
  def page = html_of("/gallery/")

  def setup
    skip "no album yet, so /gallery/ is not built" if gallery_albums.empty?
  end

  def test_one_card_per_album_with_every_photo_and_its_category
    gallery_albums.each do |a|
      card = page[%r{<details class="album" id="album-#{a["slug"]}".*?</details>}m]
      refute_nil card, "no card for #{a["slug"]}"
      assert_includes card, %(data-category="#{a["category"]}")
      assert_equal a["photos"].size, card.scan(/<li class="album__photo"/).size
    end
  end

  def dated_albums = gallery_albums.reject { |a| a["undated"] }
  def undated_albums = gallery_albums.select { |a| a["undated"] }

  def test_albums_sit_under_their_year_newest_first
    years = page.scan(/<h2 class="gallery-year__title"[^>]*>(\d{4})<\/h2>/).flatten
    assert_equal dated_albums.map { |a| a["date"][0, 4] }.uniq, years
  end

  # An undated album (the catch-all) is tied to no year: its own section after every year, headed "Anytime", with no
  # date on its card, and never inside a year's section.
  def test_undated_albums_follow_the_years_under_their_own_heading_and_show_no_date
    skip "no undated album in gallery.yml" if undated_albums.empty?
    section = page[%r{<section class="gallery-year gallery-year--undated".*?</section>}m]
    refute_nil section, "no undated section"
    assert_match(%r{<h2 class="gallery-year__title" id="gallery-undated">Anytime</h2>}, section)
    assert_equal undated_albums.map { |a| a["slug"] }, section.scan(/<details class="album" id="album-([^"]+)"/).flatten
    refute_match(/<time/, section, "an undated card has no date")
    assert_operator page.index("gallery-year--undated"), :>, page.rindex('class="gallery-year__title" id="gallery-20'), "after every year"
    years_html = page.scan(%r{<section class="gallery-year" .*?</section>}m).join
    undated_albums.each { |a| refute_includes years_html, %(id="album-#{a["slug"]}"), "#{a["slug"]} must not sit under a year" }
  end

  def test_every_strip_ships_two_hidden_arrows
    strips = page.scan('<div class="album-carousel">').size
    assert_equal dated_albums.map { |a| a["date"][0, 4] }.uniq.size + (undated_albums.empty? ? 0 : 1), strips
    assert_equal strips, page.scan(/album-carousel__prev" type="button"[^>]* hidden>/).size
    assert_equal strips, page.scan(/album-carousel__next" type="button"[^>]* hidden>/).size
  end

  def test_the_carousel_script_loads_before_the_filter
    assert_has page, 'src="/assets/js/gallery-carousel.js"', "gallery-carousel.js"
    assert_operator page.index('src="/assets/js/gallery-carousel.js"'), :<, page.index('src="/assets/js/gallery-filter.js"')
    assert File.exist?(File.join(BUILD, "assets/js/gallery-carousel.js"))
  end

  def test_chips_appear_only_for_categories_in_use_and_only_with_a_choice
    used = gallery_albums.map { |a| a["category"] }.uniq
    chips = page.scan(/data-filter="category" data-value="([^"]+)"/).flatten
    if used.size > 1
      assert_equal data("gallery")["categories"].map { |c| c["id"] } & used, chips
      assert_match(/<div class="gallery-filters" hidden>/, page, "the bar starts hidden; gallery-filter.js shows it")
    else
      assert_empty chips
    end
  end

  def test_the_page_loads_the_filter_then_the_lightbox
    assert_has page, 'id="figure-dialog"', "dialog"
    assert_has page, 'src="/assets/js/figure.js"', "figure.js"
    assert_has page, 'src="/assets/js/gallery-filter.js"', "gallery-filter.js"
    assert_operator page.index('src="/assets/js/gallery-filter.js"'), :<, page.index('src="/assets/js/figure.js"')
    assert File.exist?(File.join(BUILD, "assets/js/gallery-filter.js"))
  end

  # The slideshow that opens the page is drawn by script from the photo links in the albums below it. These guard
  # what the script cannot: that it ships hidden (no empty hero without JS), that the no-JS still is a real photo of
  # the first album, that the script is loaded before the lightbox, and that the specimen page has no autoplaying hero.
  def test_the_slideshow_ships_hidden_above_the_albums_and_builds_no_images_of_its_own
    section = page[%r{<section class="slideshow"[^>]*>.*?</section>}m]
    refute_nil section, "no slideshow on /gallery/"
    assert_match(/<section class="slideshow"[^>]* hidden>/, section, "it must start hidden; gallery-slideshow.js reveals it")
    assert_equal 2, section.scan('<span class="slideshow__layer">').size, "two stacked layers"
    refute_match(/<img\b/, section, "the script makes the images, so none ships without a source")
    assert_operator page.index('class="slideshow"'), :<, page.index('class="gallery-year"'), "the slideshow opens the page"
  end

  def test_the_noscript_still_is_the_first_albums_cover_and_resolves_to_a_file
    first = dated_albums.max_by { |a| a["slug"] } # the newest dated album; an undated one is never it
    cover = first["photos"].first
    src = "/assets/img/gallery/#{first["slug"]}/#{cover["file"]}.jpg"
    still = page[%r{<noscript>\s*<figure class="slideshow-static">.*?</figure>\s*</noscript>}m]
    refute_nil still, "no noscript still"
    assert_includes still, %(<a href="#{src}"><img src="#{src}" width="#{cover["width"]}" height="#{cover["height"]}")
    assert File.exist?(File.join(BUILD, src)), "#{src} is not in the build"
  end

  def test_the_slideshow_script_loads_before_the_lightbox
    assert_has page, 'src="/assets/js/gallery-slideshow.js"', "gallery-slideshow.js"
    assert_operator page.index('src="/assets/js/gallery-slideshow.js"'), :<, page.index('src="/assets/js/figure.js"')
    assert File.exist?(File.join(BUILD, "assets/js/gallery-slideshow.js"))
  end

  def test_the_design_language_page_has_no_autoplaying_hero
    refute_match(/<section class="slideshow"/, html_of("/design-language/"))
    refute_includes html_of("/design-language/"), 'src="/assets/js/gallery-slideshow.js"', "the page documents the slideshow in prose but must not run it"
  end
end

# The page must stay organised as albums are added. The real data has one album, so this builds a throwaway copy of the
# site with twelve (three years, three categories) and checks the index: year order, newest first inside a year, one
# card each, chip counts, and the first photo as the cover.
class GalleryScaleTest < Minitest::Test
  CATEGORIES = %w[conferences lab-life demos].freeze

  # Twelve dated albums in three years, then one tied to no year (undated: true), which must render last, under its own
  # heading and outside every year.
  def albums
    dated + [undated]
  end

  def undated
    {
      "slug" => "scale-undated", "title" => "Scale undated", "undated" => true, "category" => "demos", "consent" => "2026-01-01",
      "photos" => [{"file" => "01", "width" => 1200, "height" => 800, "alt" => "The only photo of the undated scale album"}]
    }
  end

  def dated
    (0...12).map do |i|
      date = format("%d-%02d", 2026 - i / 5, 12 - 2 * (i % 5))
      {
        "slug" => "#{GalleryRules.slug_prefix(date)}-scale-#{i}", "title" => "Scale album #{i}", "date" => date,
        "category" => CATEGORIES[i % 3], "consent" => "2026-01-01",
        "photos" => [
          {"file" => "01", "width" => 1200, "height" => 800, "alt" => "First photo of scale album #{i}, the cover"},
          {"file" => "02", "width" => 800, "height" => 1200, "alt" => "Second photo of scale album #{i}, a portrait"}
        ]
      }
    end
  end

  def test_twelve_dated_albums_and_one_undated_stay_organised_by_year_and_category
    Dir.mktmpdir("cailab-scale-") do |tmp|
      dir = File.realpath(tmp)
      src = File.join(dir, "src")
      FileUtils.mkdir_p(src)
      (Dir.children(ROOT) - %w[vendor .git _site .bundle .playwright-mcp node_modules .e2e-site test-results]).each { |n| FileUtils.cp_r(File.join(ROOT, n), src) }
      gallery = data("gallery")
      assert_empty GalleryRules.problems(albums, CATEGORIES, today: Date.new(2026, 11, 20)), "the synthetic albums are valid data"
      # Listed out of order on purpose: the page orders albums by their YYYYMMDD names, not by how the file is arranged.
      shuffled = albums.shuffle(random: Random.new(7))
      refute_equal albums, shuffled, "the shuffle must actually reorder"
      File.write(File.join(src, "_data", "gallery.yml"), gallery.merge("albums" => shuffled).to_yaml)
      out, status = Open3.capture2e({ "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile") },
        "bundle", "exec", "jekyll", "build", "--source", src, "--destination", File.join(dir, "out"), chdir: ROOT)
      assert status.success?, "build failed:\n#{out}"
      html = File.read(File.join(dir, "out", "gallery", "index.html"))

      assert_equal %w[2026 2025 2024], html.scan(/<h2 class="gallery-year__title"[^>]*>(\d{4})<\/h2>/).flatten
      ids = html.scan(/<details class="album" id="album-([^"]+)"/).flatten
      assert_equal albums.map { |a| a["slug"] }, ids, "one card per album, newest first by name, years in order, whatever the file order"
      by_year = html.scan(%r{<section class="gallery-year".*?</section>}m).map { |s| s.scan(/id="album-\d{8}-scale-(\d+)"/).flatten.map(&:to_i) }
      assert_equal [[0, 1, 2, 3, 4], [5, 6, 7, 8, 9], [10, 11]], by_year
      assert_equal 13, html.scan('<summary class="album__card"').size
      assert_equal "scale-undated", ids.last, "the undated album is last, whatever the file order"
      refute_match(/<time datetime=""/, html, "an undated card must not print an empty date")
      undated_section = html[%r{<section class="gallery-year gallery-year--undated".*?</section>}m]
      refute_nil undated_section
      assert_equal ["scale-undated"], undated_section.scan(/<details class="album" id="album-([^"]+)"/).flatten
      assert_equal 4, html.scan('<div class="album-carousel">').size, "a strip for each of the three years and one for the undated album"
      assert_equal 12, html.scan(/<img class="album__cover" src="\/assets\/img\/gallery\/\d{8}-scale-\d+\/01-thumb\.jpg"/).size, "the first photo is the cover"
      chips = html.scan(%r{data-filter="category" data-value="([^"]+)">[^<]+ <span class="chip__count">(\d+)</span>})
      assert_equal [["conferences", "4"], ["lab-life", "4"], ["demos", "5"]], chips
      assert_match(/<div class="gallery-filters" hidden>/, html)
    end
  end
end
