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

class NewsPageTest < Minitest::Test
  def test_lists_every_announcement
    assert_equal data("news").size, count_of("/news/", "news-item")
  end

  def test_nested_bullets_render_as_lists
    first = html_of("/news/")[%r{<div class="news-item__text">(.*?)</div>}m, 1]
    assert_has first, "<ul>", "first news item has no list"
    assert_has first, "<li>", "first news item has no list items"
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

  def test_only_the_directors_photo_is_used
    srcs = html_of("/people/").scan(/<img[^>]*src="([^"]+)"/).flatten
    allowed = [LAB["director_photo"], "/assets/img/logo-96.png"]
    assert_empty srcs - allowed, "photos of others need consent first"
  end
end

class ResearchPageTest < Minitest::Test
  def test_lists_themes_funding_and_media
    text = text_of("/research/")
    data("research")["themes"].each { |t| assert_has text, t["title"], "missing theme #{t["title"]}" }
    data("funding").each { |g| assert_has text, g["title"], "missing grant #{g["title"]}" }
    data("media").each { |m| assert_has text, m["title"], "missing media #{m["title"]}" }
    assert_equal data("funding").size, count_of("/research/", "funding-row")
  end
end

class JoinPageTest < Minitest::Test
  def test_lists_values_and_sections
    text = text_of("/join-us/")
    data("join")["values"].each { |v| assert_has text, v, "missing value #{v}" }
    data("join")["sections"].each { |s| assert_has text, s["title"], "missing section #{s["title"]}" }
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
    "/funding" => "/research/#funding"
  }.freeze

  # With `url:` set, the plugin writes absolute targets on the production host.
  ORIGIN = "https://#{File.read(File.join(ROOT, "CNAME")).strip}".freeze

  def stub_html(old) = File.read(File.join(BUILD, old, "index.html"))

  def test_each_old_url_has_a_redirect_page_pointing_at_its_new_home
    REDIRECTS.each do |old, target|
      assert File.exist?(File.join(BUILD, old, "index.html")), "no redirect page for #{old}"
      assert_has stub_html(old), %(url=#{ORIGIN}#{target}), "#{old} does not redirect to #{ORIGIN}#{target}"
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
