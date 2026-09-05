# Changelog

## Unreleased

**Fixed the screensaver's caption never showing a wallpaper's title once it had a credit.**
`_buildScreensaverImages`'s final `caption => length($credit) ? $credit : $title` never actually reached
the `$title` fallback, because `$credit` itself already defaulted to `$title` when there was no separate
credit - so `$credit` had length whenever `$title` did, and the ternary always took the `$credit` branch.
Net effect: whenever a wallpaper had a real photographer/artist credit, only that credit showed - the
wallpaper's own title never displayed. Fixed by sending the title as `caption` and the credit (only when
there is one, and only when distinct from the title) as `owner` - two of `ImageSourceServer.lua`'s three
independent, optional text lines, which it joins together for display, so both show together rather than
one replacing the other.

**Documented the player's own Image Viewer settings** (zoom, rotation, delay, ordering, and the text-info
toggle) in README.md - these already worked for the FilterMusic Artwork screensaver like any other Image
Viewer source, they just weren't mentioned anywhere.

**Dropped the `FilterMusicDev`/`repo-dev.xml` dev-testing convention.** It existed so a branch's build
could be installed and compared side-by-side with the real, currently-installed FilterMusic - the only
way to do that under LMS's plugin manager, since `Slim::Plugin::Extensions::Plugin::findUpdates` merges
every configured Additional Repositories feed into one list and, per plugin name, keeps only whichever
entry has the highest version (no channel/source distinction). In practice, testing happens on a
personal/non-production LMS instance with only one Additional Repositories entry configured at a time,
so that version-collision problem never actually arises - the separately-named mirror was pure upkeep
(every change hand-duplicated into a renamed copy) for a scenario that doesn't occur here. Testing a
branch now just means pointing that one Additional Repositories entry at the branch's own `repo.xml`
(raw GitHub URL) instead of the production one - see README.md's "Testing a branch" section.

## 2.3.0 (2026-09-05)

**Added an optional screensaver Image Viewer source, decoupled from the station menu entirely.**
Following the Artwork-menu revert above, a new "FilterMusic Screensaver" toggle in Settings offers
filtermusic.net's wallpapers.json feed as a selectable "Server" source for the screensaver Image Viewer
on Jivelite-based players (Squeezebox Touch/Radio, SqueezePlay) - sidestepping every conflict above by
never putting artwork into the station browse tree at all:

- `Plugin.pm`'s `initJive` now overrides `Slim::Plugin::OPMLBased::initJive` to add a `screensavers`
  field to the plugin's own top-level Jive menu entry when the toggle is on. Confirmed against
  `ralph-irving/jivelite` source: `applets/SlimMenus/SlimMenusApplet.lua` watches every top-level
  home-menu item for this field and registers each entry as a screensaver automatically, via
  `appletManager:callService("registerRemoteScreensaver", ...)` - a real, generic mechanism with no
  existing LMS plugin using it (it looks like a vestige of the discontinued SqueezeNetwork cloud photo
  apps).
- A new CLI command, `filtermusicartworkscreensaver`, fetches wallpapers.json and responds with
  `{ data: [ {image, caption}, ... ] }`, the shape `applets/ImageViewer/ImageSourceServer.lua`'s
  `imgFilesSink` expects (`chunk.data.data`, an array of `{image, caption, date, owner}`) - the same
  per-entry shape core LMS's own `slideshow`-flag response format uses in
  `Slim::Control::XMLBrowser.pm`.
- Toggling the setting calls `Slim::Control::Jive::registerPluginMenu` again immediately (confirmed
  idempotent by `id` - it replaces rather than duplicates the existing entry), so a running server picks
  up the change without restarting; an already-connected player may still need to reconnect to see it,
  since the server doesn't push a live update to a connected player's home menu on a pref change.
  Confirmed working end-to-end on SqueezePlay: "FilterMusic Artwork" appears in the Screensavers picker
  (When playing/stopped/off) after reconnecting.
- **Fixed images failing to load** ("Invalid image object found - Could not retrieve image file").
  `ImageSourceServer.lua` only recognizes a literal `http://` prefix as an already-absolute URL; the
  plain `https://filtermusic.github.io/...` URLs this feature originally sent fell through to its
  "url on current server" branch instead, which prepended the LMS server's own `http://<ip>:<port>/` in
  front of them, producing a URL that could never resolve. (A plain `http://` URL would have fared no
  better - it would have hit that Lua file's third branch, LMS's own long-decommissioned SqueezeNetwork
  image proxy.) Fixed by routing each image through LMS's own `imageproxy/` (`Slim::Web::ImageProxy.pm`)
  instead, with the literal `{resizeParams}` placeholder `ImageSourceServer.lua` looks for baked into the
  path so it substitutes real dimensions before fetching - confirmed against
  `Slim::Web::Graphics.pm`'s spec-parsing regex that this produces a real resize spec rather than
  tripping `Slim::Web::ImageProxy.pm`'s bare-extension redirect shortcut (not guaranteed to be followed
  by Jivelite's own HTTP client).
  - Follow-up, found from a real SqueezePlay debug log after the above still failed: that same
    "url on current server" branch does `"http://" .. ip .. ":" .. port .. "/" .. urlString` - it
    already appends its own `/` separator, so a `imageproxy/...` path with a **leading** slash produced
    a doubled `//` (`http://192.168.1.x:9000//imageproxy/...`) that `Slim::Web::Graphics.pm`'s
    `^imageproxy/` route never matched. Dropped the leading slash - confirmed against the server's own
    log for a real working case (a station's WebP logo conversion), which shows the identical
    `imageproxy/https://...` shape with no leading slash.

**Reverted the in-tree "Artwork" browse menu (previously numbered 2.3.0-2.4.1 on this branch, never
published to `repo.xml` - this release reuses "2.3.0" for the screensaver feature above instead).**
Browsing filtermusic.net's wallpapers.json
feed as a menu item, full-screen viewing, and a "Browse Original" source link were added, tested, and
then removed after hitting structural conflicts confirmed against real `LMS-Community/slimserver` and
`CDrummond/lms-material` source - not bugs to patch, but incompatible requirements from the same shared
item fields across clients:

- The Default web skin's one-click-to-fullscreen behavior for a leaf item requires `type => 'text'`
  (`Slim::Web::XMLBrowser.pm`). Jive/Material's native "more"/context-menu machinery requires the
  opposite - `type` must NOT be `'text'`, or `Slim::Control::XMLBrowser.pm` never assigns the item an
  `item_id` and there's no way to open a "more" screen on it at all. No single `type` value satisfies
  both.
- `jive.showBigArtwork` set on any item gets that item silently dropped by Material's own
  `browse-resp.js`, which unconditionally filters out any item carrying a top-level `showBigArtwork` flag
  unless the request's command is literally `"musicartistinfo"` (a hardcoded carve-out for LMS's own
  built-in `MusicArtistInfo` plugin). This broke Material's Artwork list outright in 2.4.0; moving the
  flag onto a secondary "Show Artwork" item inside a "more" screen worked around it in 2.4.1, but only by
  reintroducing the next problem.
- An item with `type => 'text'` and some `jive` action content but no explicit `go`/`do` gets a spurious
  fallback `go` action from `Slim::Control::XMLBrowser.pm` (re-browsing the parent feed with no item
  context) - confirmed to be the root cause of SqueezePlay's endless "select bounces back to the
  FilterMusic root" loop, Material's inert "Show Artwork"/"Browse Original" rows (the bogus `go` masked
  the intended `do`, since client action-resolution prefers `go`), and a literal `<br>` appearing in
  Material's title text (the bogus `go` made `canClickItem()` wrongly report the item as clickable,
  routing it to the wrong Vue render template).
- `weblink` on a `type => 'text'` item (tried for "Browse Original") is structurally unreachable in
  Material's click routing - `browseClick()` returns early for any text item before it ever reaches the
  `item.weblink` check - matching a real, pre-existing limitation in core LMS's own
  `Slim::Menu::TrackInfo::infoUrl` pattern, not something specific to this plugin.

What's real and worth building on instead: Jivelite's Image Viewer screensaver has a genuine "Server"
image source (`applets/ImageViewer/ImageSourceServer.lua`) that fetches a CLI response shaped
`{image, caption, date, owner}` per entry - the same shape as core LMS's own `slideshow`-flag response
format in `Slim::Control::XMLBrowser.pm` - and `applets/SlimMenus/SlimMenusApplet.lua` turns a
`screensavers` array field on any top-level home-menu item into a selectable screensaver automatically,
via `Slim::Control::Jive::registerPluginMenu`. No existing LMS plugin populates that field today (source:
`ralph-irving/jivelite`), so it's new territory to build on rather than an existing pattern to copy.

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
