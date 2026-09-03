# Changelog

## 2.3.0 (2026-09-03)

Adds a browsable **Artwork** menu item alongside the genre list, sourced from filtermusic.net's
`wallpapers.json` feed - the same feed the Material Skin background-photo feature (1.1.0-1.5.0) used
before being removed for being an invisible, unverifiable backdrop. Rather than trying that again, the
artwork is now shown directly: each entry appears as a browsable item pairing the image with its
artist/photographer credit (`body`, falling back to `title` when there's no separate credit - about a
third of the live feed's entries have `body: false`).

- **New `_fetchArtwork`/`_buildArtworkMenu`/`_decodeWallpapers`** in `Plugin.pm`, following `toplevel`'s
  existing fetch-decode-build pattern. The wallpapers.json fetch happens after the station menu is
  built, and a failure or parse error there is only ever logged - it never blocks or breaks station
  browsing, which doesn't depend on it.
- **Reintroduces `_decodeEntities`** (removed in 2.2.0 along with the old HTML-scraping parser) since
  wallpapers.json's `body`/`title` credit text is HTML that can contain entities like `&nbsp;`.
- Caching is unchanged: the Artwork node is appended to the menu before it's cached, so it's covered by
  the same `CACHE_TTL` window as the rest of the menu, with no separate cache needed.

## 2.2.0 (2026-08-28)

filtermusic.net's author added a JSON feed specifically for this plugin at
`https://filtermusic.net/stations.json`, regenerated on every site deploy - this release moves the
plugin onto it, replacing the homepage-scraping approach from the 2026 rewrite.

- **Replaced HTML scraping with the JSON feed.** `_parseMenu` and `_decodeEntities` (the two-pass
  regex parser and hand-rolled entity decoder needed to pull station data out of filtermusic.net's
  server-rendered markup) are gone, replaced by `_decodeFeed`/`_buildMenu`, which just decode the feed
  with `JSON::XS::VersionOneAndTwo` (bundled with LMS, same no-risky-dependency approach as before) and
  walk its `genres`/`stations` arrays. Nothing here depends on filtermusic.net's markup any more, so a
  CSS/markup change on that site can no longer break parsing.
- **Added a short in-memory cache.** A successful fetch is now reused for `CACHE_TTL` (5 minutes)
  before the next visit refetches, cutting down on repeat requests from browsing in and back out of the
  menu. Past that window, if the feed's `generated` timestamp comes back unchanged - i.e. filtermusic.net
  hasn't redeployed - the previously-built menu is reused rather than rebuilt from the same data.
- **Stations carry a separate `description`** (used by LMS for the station's detail/info view), since
  the feed exposes it as its own field already stripped of markup - the feed also exposes `homepage`
  and `playlist` per station, unused by the plugin for now. The station's displayed `name` still folds
  the description in as `"$title - $desc"`, matching the browse-menu and now-playing title format the
  2.1.x scraping releases used - an earlier draft of this migration dropped that formatting and showed
  just the bare title, which was a regression from 2.1.x.
- **Fixed station logos missing from the Now Playing screen on JSON-RPC-driven clients** (the default
  web UI, Material Skin, the app - anything that talks to LMS via `Slim::Control::XMLBrowser` rather
  than the classic server-rendered web skin). Each station now sets both `icon` and `image` to its
  `logo` URL: `icon` is what the browse-menu list and Jive icon read, but the code path that actually
  seeds a playing stream's Now Playing artwork cache (`Slim::Control::XMLBrowser`'s and
  `Slim::Web::XMLBrowser`'s "keep track of station icons" `remote_image_` caching, confirmed by reading
  `Slim::Control::XMLBrowser.pm` and `Slim::Web::XMLBrowser.pm` directly) only ever reads `image` or
  `cover`, never falling back to `icon` - so a station with `icon` set but no `image` played back with
  no artwork on those clients, even though the classic web skin's separate `play`-action code path
  (which *does* fall back to `icon`) made it look fine there.
- **filtermusic.net's `logo` URLs are WebP - this needs LMS 9.1.0 or newer, not a plugin or
  filtermusic.net change.** LMS can't decode WebP with its own artwork resizer (`Image::Scale`, used by
  `Slim::Utils::GDResizer.pm`); it instead redirects `.webp` artwork through an external conversion
  service, `https://api.lms-community.org/img/compatible/<url>`, in `Slim::Web::ImageProxy.pm`. Diffing
  that file between the `9.0.3` and `9.1.1` tags in LMS-Community/slimserver shows this entire mechanism
  - the `.webp` detection, the conversion redirect, everything - was added between those two releases;
  it does not exist at all in `9.0.3` or earlier. An install on `9.0.3` just logs
  `Artwork resize for imageproxy/.../logo.webp/... failed` for every station and never shows the logo,
  in Now Playing (`/music/current/cover.jpg`, traced through `Slim::Web::Graphics.pm`) and in the
  **Default** web skin's browse-list thumbnails alike (`HTML/Default/xmlbrowser.html`'s `resizeimage`
  filter calls the same `proxiedImage()`/`/imageproxy/` pipeline) - confirmed against a real install by
  comparing a `9.0.3` QNAP Docker server (broken, matching log line above) against a `9.1.1` install
  (working) side by side. Upgrading the `9.0.3` server to `9.1.0`+ fixes it completely, with no plugin
  or filtermusic.net change needed. (The literally-named **"Classic"** skin is a separate, real
  limitation regardless of LMS version or image format: it has no `xmlbrowser.html` of its own and
  falls back to LMS's bare legacy template, `HTML/EN/xmlbrowser.html`, confirmed via
  `Slim::Web::Template::SkinManager.pm` and `HTML/Classic/skinconfig.yml`'s missing `skinparents`,
  which is gated to `item.type == 'text'` and never shows artwork for `type => 'audio'` items at all.)
- Bumped the plugin's `User-Agent` string to `2.0` to distinguish feed requests from the old
  markup-scraping version's traffic on filtermusic.net's side.

## 2.1.2 (2026-08-24)

Actually ships the `fm.svg` glyph scaling fix from `85c1c39` ("Scale fm.svg glyph to reduce whitespace
in 24x24 viewBox"), which was merged into the source tree but never released: `repo.xml` was still
pointing at `FilterMusic_2_1_1.zip`, built before that fix, so every real install has been getting the
old, small-in-its-viewBox icon regardless of which version was shown as installed. No source changes in
this release - just rebuilding and shipping `FilterMusic_2_1_2.zip` from the current tree, and updating
`repo.xml` to point at it, so the already-committed fix actually reaches installs.

## 2.1.1 (2026-08-23)

Fixes 2.1.0: the `icon` key it added to the `initPlugin` call did nothing.
`Slim::Plugin::OPMLBased::initPlugin` never reads an `icon` argument - it only ever calls
`$class->_pluginDataFor('icon')`, which is sourced from `install.xml`'s `<icon>` tag and feeds the
Jive window `icon-id`, the CLI `radios` query, and the legacy `icon` field alike (verified directly
against `Slim::Plugin::OPMLBased.pm` and `Slim::Plugin::Base.pm`).

- **Removed** the dead `icon` argument from `initPlugin` in `Plugin.pm`.
- **Pointed `install.xml`'s `<icon>` at `fm_svg.png`** instead of the old `fm.png` - this is the
  actual, single source of truth for the top-level menu icon (and also still drives the plugin's
  listing icon in the extension browser, so the two are now unified rather than split as 2.1.0
  claimed).
- Confirmed `proxiedImage()` (which wraps `_pluginDataFor('icon')` before use) passes local
  relative paths through unchanged - it only rewrites `http(s)://` URLs - so the `_svg.png` → `.svg`
  filename convention Material Skin relies on still applies.

## 2.1.0 (2026-08-23)

Closes [#1](https://github.com/d5c0d3/filtermusic_sb/issues/1): the FilterMusic top-level menu node
now has an icon.

- **Set the top-level menu `icon`** in `initPlugin` to
  `plugins/FilterMusic/html/images/fm_svg.png` (previously unset, so players/skins fell back to a
  generic radio icon).
- **Added a Material Skin variant.** Material recolours any SVG icon whose fill/stroke is `#000` to
  match the active theme, and swaps in a same-named `.svg` file for any icon path ending `_svg.png`
  (confirmed by reading Material's own `icon-mapping.js` and comparing against its bundled icons,
  e.g. `genre.svg`: `viewBox="0 0 24 24"`, single `fill="#000"` path, no `width`/`height`). Added
  `fm.svg` alongside `fm_svg.png` - a 24x24, `#000`-fill/stroke SVG built from the same "fm" mark -
  so Material Skin renders and themes it automatically across its light/dark/coloured colour
  schemes, while every other skin/client just uses the `fm_svg.png` raster fallback.
- The raster fallback (`fm_svg.png`) uses the newer dark "fm" badge design rather than the older
  light `fm.png` badge still used for the plugin's install-listing icon in `install.xml` - the two
  aren't currently unified.

## 2.0.0 (2026-08-23)

Consolidates a run of small releases (1.1.0–1.5.0) that turned out to be iteration on top of 1.0.0
rather than real milestones, into a single entry.

- **Tried, then removed, an optional Material Skin background photo.** Added in 1.1.0, refined over
  1.2.0–1.3.0 (live per-visit refresh, then a simplified no-cache design), fixed twice more (a broken
  settings-template expression, then a stale scrape after filtermusic.net moved wallpaper selection
  client-side) - but the background never actually appeared in testing, and with no way to verify a
  Material Skin client's rendering from outside it, it wasn't worth chasing further for a feature that
  was always cosmetic. Removed entirely; the settings page is back to just the "Add to Favorites"
  shortcut it always was otherwise.
- **Removed the persistent station-list cache.** Once every visit was already doing a live fetch (for
  the background photo, since removed), caching the parsed station list separately only saved a small
  amount of local regex work while adding real complexity. Every visit now fetches and parses
  filtermusic.net fresh; the only state kept in memory is the last successful result, used as a
  fallback if a fetch ever fails.
- **Fixed a silent-logging bug**: the fetch-failure path logged via `$log->warn(...)`, but the plugin's
  log category defaults to level `ERROR`, and `WARN` sits below that threshold in `Slim::Utils::Log`'s
  severity order (`DEBUG < INFO < WARN < ERROR < FATAL`) - so "could not reach filtermusic.net"
  produced no visible log line at all under default settings.
- **Added `LICENSE` (MIT)**, matching comparable community LMS plugins (`lyr-radio-browser`,
  `lms-somafm`) and the spirit of the original 0.2 release's own "feel free to use my script, just
  credit it" note.
- **Switched attribution to the `d5c0d3` handle** throughout (a pseudonym is legally sufficient for
  copyright attribution) and **pointed contact info at GitHub Issues** instead of a public email
  address.

## 1.0.0 (2026-08-22)

Full rewrite to revive the plugin on current Lyrion Music Server / LMS installs. The 0.2 release
(2011) no longer worked at all on modern servers.

- **Fixed fatal load failure**: dropped `HTML::TreeBuilder`, which LMS ships without its
  `HTML::Tagset` dependency (`Can't locate HTML/Tagset.pm in @INC`,
  [Logitech/slimserver#594](https://github.com/Logitech/slimserver/issues/594)). The station list is
  now parsed with plain regexes against LMS's own bundled Perl, no extra CPAN modules required.
- **Rebuilt the parser against the current filtermusic.net markup.** The site was rebuilt (Astro)
  since 2011; the old `/accordion` jQuery markup and the `/feed` RSS endpoint (used for the old
  "Newly Added" category) are both gone. The current front page embeds every station, including its
  direct stream URL, description and artwork, as data attributes on the page itself, so the plugin
  now needs only a single request instead of two.
- **Removed the "Newly Added" feature** — it depended on the RSS feed, which no longer exists, and
  had a pre-existing race condition between its two unsynchronized async HTTP fetches.
- **Added response caching** (`Slim::Utils::Cache`, default 6 hours, configurable) so browsing the
  menu doesn't re-fetch and re-parse filtermusic.net on every visit.
- **Added station artwork** using the image already provided per-station by the site.
- **Added proper error handling** — fetch/parse failures now surface a real OPML error message
  instead of an empty menu or a raw HTTP error string shown as a fake station.
- **Fixed the Settings page**: added a working `Settings.pm`, `optionsURL` in `install.xml` (so
  "Manage Plugins" links to it directly), a cache-duration preference, and a "Clear Cache Now"
  action. The old page linked to a case-mismatched, unhandled `?reset=1` URL that never did anything.
- **Updated version targeting**: `install.xml`/`repo.xml` now declare
  `<id>LogitechMediaServer</id>`, `minVersion 8.0`, `maxVersion 9.*` (was `SlimServer` 7.6–7.*, which
  is invisible to any current LMS install) and set `<category>radio</category>`.
- **Source is now tracked in git** under `FilterMusic/` instead of only existing inside a committed
  `.zip`.

## 0.2 (2011-10-10)

Initial public release.
