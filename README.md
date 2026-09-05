# FilterMusic plugin for Lyrion Music Server

Browse the internet radio stations curated on [FilterMusic.net](https://filtermusic.net) from inside
[Lyrion Music Server](https://lyrion.org) (formerly Logitech Media Server / SlimServer), organized by
the same genre categories used on the site (House/Dance, Techno/Trance, Jazz, Rock/Metal, ...).

This repository is both the plugin's source and its self-hosted plugin repository (`repo.xml`), which
GitHub Pages serves at <https://d5c0d3.github.io/filtermusic_sb/repo.xml>.

## Features

- **Browse by genre**, matching filtermusic.net's own categories (House/Dance, Techno/Trance,
  Electronica/Industrial, Breaks/DrumnBass, HipHop/Rap, Reggae/Dub/Dancehall, Funk/Soul/Disco, Lounge
  Grooves, Downtempo/Ambient, Various/Mainstream, 60s/70s/80s/90s, Classical, Jazz, Rock/Metal,
  International/Ethnic).
- **Direct playback** - each station plays straight from the stream URL filtermusic.net already lists;
  no extra per-station page fetch.
- **Station artwork and descriptions** for every entry, read straight from filtermusic.net's own feed.
- **Add to Favorites** shortcut from the Settings page, for pinning FilterMusic to your Favorites menu.
- **Optional screensaver Image Viewer source** - a Settings-page toggle offers filtermusic.net's
  artwork as a "Server" source for the screensaver Image Viewer on Jivelite-based players (Squeezebox
  Touch/Radio, SqueezePlay). See "How it works" below.
- **Resilient to filtermusic.net being down or changing**: if a visit's fetch fails, or the feed's
  format changes enough to break parsing, the plugin falls back to the last successful load instead of
  showing an empty menu or hard error - see "How it works" below.
- **Lightly cached** - a successful load is kept in memory for a few minutes, so browsing in and back
  out of the FilterMusic menu repeatedly doesn't refetch every time, while still staying close to what
  filtermusic.net currently lists. See "How it works" below.
- **No risky dependencies** - the original 0.2 release depended on a module LMS doesn't fully bundle
  and failed to load on any current server; this rewrite only uses LMS's own bundled Perl (including
  its bundled JSON support). See "History" below.

## Installing

In LMS: **Settings → Plugins → Additional Repositories**, add:

```
https://d5c0d3.github.io/filtermusic_sb/repo.xml
```

The FilterMusic plugin will then appear in the plugin list to install.

### Testing a branch (dev build)

To try out a branch's code on a real LMS server without touching the installed FilterMusic plugin or
its config, install it as a second, separately-named plugin that runs fully independently:

1. Duplicate `FilterMusic/` into `FilterMusicDev/`, renaming every identifying piece so it can never
   collide with the real plugin: the Perl package (`Plugins::FilterMusicDev::Plugin`/`::Settings`), the
   OPML `tag`, the `Slim::Utils::Prefs` namespace, the log category, every string key in `strings.txt`
   (and the display name/description text itself, e.g. "FilterMusic (Dev)"), and the `install.xml`
   `<name>`/`<module>`/paths. Nothing under `FilterMusicDev/` should read `FilterMusic` anywhere it
   matters functionally.
2. Zip it up (`FilterMusicDev_<version>.zip`, same layout convention as the real release zips below) and
   commit it, along with a small standalone `repo-dev.xml` (not the real `repo.xml`) with one `<plugin>`
   entry for `FilterMusicDev`, its `<url>` pointing at that zip via
   `https://raw.githubusercontent.com/d5c0d3/filtermusic_sb/<branch>/FilterMusicDev_<version>.zip` -
   GitHub Pages only serves `repo.xml` from the default branch, so a branch under test needs raw content
   instead.
3. In LMS, add a *second* Additional Repositories entry (alongside the real one) pointing at that
   branch's `repo-dev.xml`, also via `raw.githubusercontent.com`. "FilterMusic (Dev)" then appears in
   the plugin list to install/update independently.

Two gotchas worth knowing up front:

- **LMS decides whether an update is offered by comparing the `<version>` string, not the zip's
  content.** `FilterMusicDev`'s version has to be bumped on every rebuild pushed to the branch (its own
  independent numbering, e.g. `2.2.0.1` → `2.2.0.2` - unrelated to `FilterMusic/install.xml`'s real,
  eventual release version), or LMS won't notice a new build is even available.
- **Both GitHub's raw-content CDN and LMS's own repository-list cache can serve a stale copy** even
  after that version bump. If "FilterMusic (Dev)" doesn't show the new version, append a cache-busting
  query string to the Additional Repositories URL (e.g. `?v=<anything-new>`) to force a fresh fetch
  before assuming something is actually broken.

When done testing, uninstall "FilterMusic (Dev)" and remove its Additional Repositories entry - the real
FilterMusic install is never touched by any of this.

## Requirements

- Lyrion Music Server / Logitech Media Server 8.0 or newer.

## How it works

`FilterMusic/Plugin.pm` fetches `https://filtermusic.net/stations.json`, a feed maintained by
filtermusic.net specifically for this plugin and regenerated on every site deploy, and decodes it
directly - there's no HTML to parse and no public API beyond this one feed. Each station in the feed
already carries its direct stream URL, name, description and artwork, so a single request builds the
whole menu:

```
{ generated, genres: [ { name, page, stations: [
    { name, description, page, homepage, stream, playlist, logo } ] } ] }
```

A successful fetch is cached in memory for a few minutes (`CACHE_TTL` in `Plugin.pm`), so repeatedly
browsing in and back out of the FilterMusic menu doesn't refetch every time. Once that window passes,
the feed is fetched again, but if its `generated` timestamp hasn't moved since the last fetch - i.e.
filtermusic.net hasn't redeployed - the menu already built from it is reused rather than rebuilt from
the same data. Browsing *within* FilterMusic (into a genre, a station) never calls back into the plugin
at all, since the whole subtree is already in the response for the top-level menu. The only state kept
beyond the cache window is the last successful result, used as a fallback if a fetch or parse ever
fails.

Because this depends on the feed's current shape, a breaking change to it can break parsing. If
browsing FilterMusic in LMS starts showing an empty menu or a "could not read the station list" error,
check `FilterMusic/Plugin.pm`'s `_decodeFeed`/`_buildMenu` against the feed's current shape first.

### Screensaver Image Viewer source

Turning on "FilterMusic Screensaver" in Settings adds a `screensavers` field to the plugin's top-level
Jive menu entry (see `initJive` in `Plugin.pm`). Jivelite's own `SlimMenusApplet.lua` watches every
top-level home-menu item for that field and registers each entry as a selectable "Server" source for the
screensaver Image Viewer, whose `ImageSourceServer.lua` fetches images by calling the entry's `cmd` - a
new CLI command, `filtermusicartworkscreensaver`, registered alongside the main menu. It fetches
`https://filtermusic.net/wallpapers.json` (the same feed the long-removed Material Skin background-photo
feature, 1.1.0-1.5.0, once used) and responds with `{ data: [ {image, caption}, ... ] }`, the shape
`ImageSourceServer.lua` expects.

This only affects Jivelite-based players (Squeezebox Touch/Radio, SqueezePlay) - it has no effect on
Material Skin or the Default web skin, which don't have a screensaver Image Viewer. Toggling the setting
re-registers the menu entry immediately (`Slim::Control::Jive::registerPluginMenu` is idempotent by
`id`, so this replaces rather than duplicates it), which newly-connecting players pick up right away; an
already-connected player may still need to reconnect to see the change, since the server doesn't push a
live update to its home menu on a pref change. Confirmed working on SqueezePlay: after reconnecting,
"FilterMusic Artwork" appears in the Screensavers picker (When playing / When stopped / When off),
alongside "Image Viewer" and "Clock" - it is its own separate screensaver entry, not a new source added
to Image Viewer's own "Sources" screen, which is a fixed, hardcoded list (`http`/`flickr`/`card`/`usb`/
`storage`) that can't be extended from a server-side plugin at all.

Each image is served through LMS's own `imageproxy/` (`Slim::Web::ImageProxy.pm`) rather than pointing
`ImageSourceServer.lua` straight at filtermusic.net's own URLs - that Lua file only recognizes a literal
`http://` prefix as "already absolute" (a plain `https://` URL falls through to a branch that mangles it
by prepending the LMS server's own address in front of it), and even a plain `http://` external URL would
hit its third branch, LMS's own long-decommissioned SqueezeNetwork image proxy. Routing through
`imageproxy/` sidesteps both. That same branch already appends its own `/` before the path
(`"http://" .. ip .. ":" .. port .. "/" .. urlString`), so the `image` field must **not** have a leading
slash of its own - one did, briefly, and produced a doubled `//` that never matched
`Slim::Web::Graphics.pm`'s `imageproxy/` route at all.

Confirmed working end-to-end on SqueezePlay: the screensaver cycles through filtermusic.net's artwork
with captions, images loading via the imageproxy route above.

## Known issues

**Station logos need LMS 9.1.0 or newer.** The feed's `logo` URLs are WebP. LMS's own artwork resizer
(`Image::Scale`) can't decode WebP at all - `Slim::Web::ImageProxy.pm` instead redirects `.webp`
artwork through an external conversion service (`https://api.lms-community.org/img/compatible/<url>`)
before displaying it, and that entire mechanism was only added to LMS between the `9.0.3` and `9.1.1`
releases (diffed directly against LMS-Community/slimserver's tagged source). On `9.0.3` or older, a
WebP logo just fails to resize - logged as `Artwork resize for imageproxy/.../logo.webp/... failed` -
everywhere LMS itself renders artwork: Now Playing (`/music/current/cover.jpg`) and the **Default** web
skin's browse-list thumbnails alike, since both go through the same `proxiedImage()`/`/imageproxy/`
pipeline. **Upgrade the LMS/Lyrion server to 9.1.0+ and it resolves itself, with no plugin or
filtermusic.net change needed** - confirmed by comparing a `9.0.3` install (broken) against a `9.1.1`
install (working) side by side. (The literally-named **"Classic"** skin is a separate, real limitation
regardless of LMS version or image format: it has no `xmlbrowser.html` of its own and falls back to
LMS's bare legacy template, which never shows artwork for `type => 'audio'` items at all.)

## History

The original 0.2 release (2011) scraped an older, jQuery-accordion version of the site using
`HTML::TreeBuilder`. That module's dependencies (`HTML::Tagset`) are not bundled with LMS, so the
0.2 plugin fails to load at all on any reasonably modern server
(see [Logitech/slimserver#594](https://github.com/Logitech/slimserver/issues/594)). Version 1.0.0 was a
full rewrite: no `HTML::TreeBuilder` dependency, updated target versions
(`LogitechMediaServer` 8.0–9.*), a working Settings page, and parsing rebuilt against the current
filtermusic.net markup. Version 2.0.0 consolidates a run of small follow-up releases that briefly added
(and then removed, after it turned out unworkable in practice) an optional Material Skin background
photo, and simplified the caching approach down to a fresh fetch on every visit. Version 2.2.0 moved
off homepage-markup scraping entirely onto a `stations.json` feed filtermusic.net now publishes for
this plugin, and added the lightweight in-memory cache described above. See `CHANGELOG.md` for the
full detail.

## Credits

FilterMusic.net is created and curated by Spyros. Every station, genre, and image this plugin
displays is their work, not this project's. When I contacted them about reviving the plugin, they
offered immediately to help and built a data feed for it, so it no longer needs to scrape the
website. Thank you, Spyros.

## License

MIT - see `LICENSE`. That covers this plugin's own code; the station data and artwork it reads from
filtermusic.net remain filtermusic.net's own content, not licensed by this project.
