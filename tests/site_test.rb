require "minitest/autorun"
require "cgi"
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

# A publication may declare a figure and/or a video. The files sit flat in assets/img (the stray-file
# test does not recurse): pub-<slug>.jpg (large), pub-<slug>-thumb.jpg, and for a video pub-<slug>-poster.jpg.
def figure_pubs = data("publications").select { |p| p["figure"] }
def video_pubs = data("publications").select { |p| p["video"] }

def publication_images
  figure_pubs.flat_map { |p| ["pub-#{p["figure"]["slug"]}.jpg", "pub-#{p["figure"]["slug"]}-thumb.jpg"] } +
    video_pubs.map { |p| "pub-#{p["video"]["slug"]}-poster.jpg" }
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
  INTERNAL = %w[Gemfile Gemfile.lock AGENTS.md CLAUDE.md README.md tests bin design-demos vendor].freeze

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
    allowed = [LAB["director_photo"], "/assets/img/logo-96.png"] + photo_people.map { |p| p["photo"] }
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

  def test_a_paper_appears_once_across_all_areas
    all = CARDS + MORE
    assert_equal all.uniq, all, "a paper is listed twice: #{all.select { |i| all.count(i) > 1 }.uniq}"
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
      assert_has html, %(<li class="publication-row" id="pub-#{id}">), "no row anchor for #{id}"
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
      assert_has html, "/assets/img/pub-#{paper["figure"]["slug"]}-thumb.jpg", "no thumbnail for #{id}"
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
  FIXED_IMAGES = %w[logo-480.png logo-96.png kenny-320.jpg apple-touch-icon.png].freeze
  ALLOWED_IMAGES = (FIXED_IMAGES + photo_people.map { |p| File.basename(p["photo"]) } + publication_images).freeze

  def test_assets_img_holds_only_the_expected_files_in_source
    found = Dir.children(File.join(ROOT, "assets", "img")).sort
    assert_equal ALLOWED_IMAGES.sort, found, "unexpected file(s) in assets/img"
  end

  def test_no_other_image_is_published
    images = Dir.glob(File.join(BUILD, "**", "*.{png,jpg,jpeg,gif,webp,svg}")).map { |f| File.basename(f) }
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
    Dir.glob(File.join(ROOT, "assets", "img", "*.jpg")).each do |path|
      found = jpeg_segments(path).map(&:first) & [APP1_EXIF_XMP, APP13_IPTC, COMMENT]
      assert_empty found, "metadata segment(s) #{found.map { |m| format("0x%X", m) }.join(", ")} in #{File.basename(path)}"
    end
  end
end

# The thumbnail is a plain link to the large image, so it still works without JavaScript.
class PublicationFigureTest < Minitest::Test
  PUBS = data("publications")
  IMG = File.join(ROOT, "assets", "img")

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
      large = File.join(IMG, "pub-#{fig["slug"]}.jpg")
      thumb = File.join(IMG, "pub-#{fig["slug"]}-thumb.jpg")
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
      assert_match %r{<a class="publication-row__figure" href="[^"]*/assets/img/pub-#{slug}\.jpg"}, row
      assert_match %r{<img src="[^"]*/assets/img/pub-#{slug}-thumb\.jpg" alt="#{Regexp.escape(alt)}"}, row
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
  IMG = File.join(ROOT, "assets", "img")

  def test_each_video_has_an_id_title_and_a_16_by_9_poster
    video_pubs.each do |pub|
      video = pub["video"]
      assert_match(/\A[\w-]{11}\z/, video["youtube"].to_s, "not a YouTube id: #{pub["title"]}")
      assert_match(/\A[a-z0-9-]+\z/, video["slug"].to_s, "bad video slug: #{pub["title"]}")
      assert video["title"].to_s.strip.size > 5, "video needs a title: #{pub["title"]}"
      poster = File.join(IMG, "pub-#{video["slug"]}-poster.jpg")
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
      assert_match %r{\A/assets/img/[\w-]+\.jpg\z}, person["photo"], "bad photo path for #{person["name"]}"
      assert File.size?(File.join(ROOT, person["photo"])), "missing photo file for #{person["name"]}"
    end
  end

  def test_the_directors_photo_file_exists
    path = data("lab")["director_photo"]
    assert_match %r{\A/assets/img/[\w-]+\.jpg\z}, path
    assert File.size?(File.join(ROOT, path)), "missing director photo: #{path}"
  end

  def test_every_entry_has_a_name_and_a_role_or_note
    PEOPLE["members"].each { |p| assert p["role"].to_s.strip != "", "#{p["name"]} has no role" }
    (PEOPLE["collaborators"] + (PEOPLE["collaborators_former"] || [])).each { |p| assert p["role"].to_s.strip != "", "#{p["name"]} has no role" }
    (PEOPLE["alumni_graduate"] + PEOPLE["alumni_undergraduate"]).each { |p| assert p["note"].to_s.strip != "", "#{p["name"]} has no note" }
  end
end
