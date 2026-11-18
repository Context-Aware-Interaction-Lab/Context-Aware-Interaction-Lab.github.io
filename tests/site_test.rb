require "minitest/autorun"
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

# Only current members and collaborators may carry a photo (consent given 2026-11-18).
def photo_people = data("people").values_at("members", "collaborators").flatten.select { |p| p["photo"] }

NAV = data("nav")
INTERNAL_PAGES = NAV.reject { |n| n["external"] }.map { |n| n["url"] }
PAGES = (["/"] + INTERNAL_PAGES + ["/design-language/"]).freeze

def html_of(page)
  file = page == "/" ? "index.html" : File.join(page, "index.html")
  File.read(File.join(BUILD, file))
end

def text_of(page) = html_of(page).gsub(/<[^>]+>/, " ").gsub(/\s+/, " ")

def count_of(page, css_class) = html_of(page).scan(/<li class="#{css_class}[ "]/).size

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
          path, = href.split("#")
          target = File.join(BUILD, path.end_with?("/") ? File.join(path, "index.html") : path)
          assert File.exist?(target), "#{page}: dead link #{href}"
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

  def test_lists_every_research_focus
    LAB["foci"].each { |focus| assert_has text_of("/"), focus, "home lacks focus: #{focus}" }
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
    (PEOPLE["members"] + PEOPLE["collaborators"] + PEOPLE["alumni_graduate"] + PEOPLE["alumni_undergraduate"])
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
end

class ResearchPageTest < Minitest::Test
  def test_lists_themes_and_media
    text = text_of("/research/")
    data("research")["themes"].each { |t| assert_has text, t["title"], "missing theme #{t["title"]}" }
    data("media").each { |m| assert_has text, m["title"], "missing media #{m["title"]}" }
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

  def test_scholarship_links_are_kept
    html = html_of("/join-us/")
    assert_has html, "https://www.sutd.edu.sg/Admissions/Graduate/Scholarships", "scholarship link lost"
  end
end

# The old Google Site had /home, /media and /funding. People have those saved.
class OldUrlRedirectsTest < Minitest::Test
  REDIRECTS = {
    "/home" => "/",
    "/media" => "/research/#media",
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
  ALLOWED_IMAGES = (FIXED_IMAGES + photo_people.map { |p| File.basename(p["photo"]) }).freeze

  def test_assets_img_holds_only_the_expected_files_in_source
    found = Dir.children(File.join(ROOT, "assets", "img")).sort
    assert_equal ALLOWED_IMAGES.sort, found, "unexpected file(s) in assets/img"
  end

  def test_no_other_image_is_published
    images = Dir.glob(File.join(BUILD, "**", "*.{png,jpg,jpeg,gif,webp,svg}")).map { |f| File.basename(f) }
    assert_empty images - ALLOWED_IMAGES, "unexpected image(s) in the published site"
  end
end

# Moving someone between lists is easy to half-do. These guard the data, not the pages.
class PeopleDataTest < Minitest::Test
  PEOPLE = data("people")

  def names(key) = PEOPLE[key].map { |p| p["name"] }

  def test_nobody_is_listed_twice_anywhere
    all = PEOPLE.keys.flat_map { |key| names(key) }
    dupes = all.group_by(&:itself).select { |_, v| v.size > 1 }.keys
    assert_empty dupes, "listed more than once: #{dupes.join(', ')}"
  end

  def test_current_members_are_not_also_alumni
    current = names("members") + names("collaborators")
    alumni = names("alumni_graduate") + names("alumni_undergraduate")
    assert_empty current & alumni, "both current and alumni: #{(current & alumni).join(', ')}"
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

  # Consent covers current members and collaborators only; alumni are never photographed here.
  def test_alumni_carry_no_photo
    (PEOPLE["alumni_graduate"] + PEOPLE["alumni_undergraduate"]).each do |person|
      refute person.key?("photo"), "alumni must not carry a photo: #{person["name"]}"
    end
  end

  def test_every_entry_has_a_name_and_a_role_or_note
    PEOPLE["members"].each { |p| assert p["role"].to_s.strip != "", "#{p["name"]} has no role" }
    PEOPLE["collaborators"].each { |p| assert p["role"].to_s.strip != "", "#{p["name"]} has no role" }
  end
end
