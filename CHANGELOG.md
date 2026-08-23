# Changelog

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
