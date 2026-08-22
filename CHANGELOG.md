# Changelog

## 1.1.0 (2026-08-22)

- **Added an optional Material Skin background photo.** filtermusic.net renders a random full-page
  wallpaper photo (with a credit caption) on every homepage load; the plugin now piggybacks on the
  station-list request it already makes to grab that same photo and applies it as the `image` on
  each genre category. Skins that read a menu node's own icon as its browse backdrop (currently
  Material Skin, when its own "Draw background" setting is on) will show it; every other client
  ignores the extra field, the same as the per-station artwork already added in 1.0.0. It changes
  whenever the station-list cache refreshes (default every 6h) rather than per-category, to avoid
  adding extra requests to filtermusic.net beyond the one fetch the plugin already makes.
- Added a `showBackdrop` setting (on by default) to turn this off, and the settings page now shows
  the currently-applied photo's credit.
- Fixed the settings page's form field names: `Slim::Web::Settings`'s base `handler` expects them
  prefixed `pref_<name>` (e.g. `pref_cacheTTLMinutes`) to be saved at all — the 1.0.0 page saved
  cache-duration changes under an unprefixed name, which the base handler never picked up.

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
