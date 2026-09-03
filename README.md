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
- **Browse artwork with artist credits** - a separate "Artwork" menu item lists the images featured on
  filtermusic.net, each paired with its artist/photographer credit. Selecting one shows it full-screen
  (on clients that support it); its "more" screen offers a **Browse Original** link back to the source
  page when the entry links to one. See "How it works" below.
- **Add to Favorites** shortcut from the Settings page, for pinning FilterMusic to your Favorites menu.
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

Once the station menu is built, the plugin also fetches `https://filtermusic.net/wallpapers.json` and
appends an "Artwork" node to the menu from it - `_fetchArtwork`/`_buildArtworkMenu` in `Plugin.pm`. This
is the same feed the Material Skin background-photo feature (added 1.1.0, removed 1.5.0) used to pick an
invisible backdrop image; here each entry is instead shown as a browsable item pairing the image with
its artist/photographer credit:

```
[ { title, body, field_wallpaper } ]
```

`field_wallpaper` is a filename appended to `https://filtermusic.github.io/wallpaper/` for the image
URL; the credit shown is `body` (HTML, stripped and entity-decoded) when present, or `title` otherwise -
`body` comes back as the JSON boolean `false`, not an empty string, on entries with no credit.

Unlike `stations.json`, wallpapers.json has no `generated` timestamp to check as a whole, so
`_buildArtworkMenu` detects change per entry instead: `%lastArtworkByKey` remembers each entry's
title/credit text keyed by its `field_wallpaper` filename (the closest thing this feed has to a stable
id), and an entry whose text is unchanged since the last fetch reuses the item already built for it
rather than re-stripping/re-decoding the same text again. This doesn't shrink the fetch itself -
wallpapers.json is one flat array with no way to request only the changed entries - it only avoids
redundant per-entry rebuild work. A failure to fetch or parse wallpapers.json falls back to the last
known good Artwork node if one exists, the same "keep the last known good result" fallback the station
menu uses; it never blocks or breaks station browsing either way.

Each Artwork item also carries a `jive` block (`_buildArtworkItem`) giving Jive/app/JSON-RPC clients two
actions the Default web skin already gets for free: selecting the item shows the image full-screen
(`actions.do` targets LMS's own stock `artwork` command, plus `showBigArtwork => 1` - the same mechanism
`Slim::Menu::TrackInfo`/`AlbumInfo` use for "Show Artwork"), and its "more" screen shows the credit plus,
when the raw `body` contains a source `<a href="...">`, a **Browse Original** link to it. That "more"
screen is powered by a small CLI command this plugin registers itself
(`Slim::Control::Request::addDispatch` in `initPlugin`, `filtermusicartworkinfo` /
`filtermusicdevartworkinfo` per plugin so the two don't collide when both are installed) - `_artworkInfo`
bridges the dispatch's `$request`-based calling convention into a normal feed sub via
`Slim::Control::XMLBrowser::cliQuery`, the same pattern `Slim::Plugin::Podcast::Plugin::showInfo` uses;
`_artworkInfoFeed` builds the actual content. The **Browse Original** link is only offered when
`Slim::Utils::Misc::canFollowWeblinks($client)` is true for whichever client requested that "more"
screen - real Squeezebox hardware (talking SlimProto, not HTTP) never sets a `controllerUA` and so never
gets a dead link; it sees the plain source URL as text instead. That check runs fresh every time "more"
is pressed, not baked into the shared, cached top-level menu, since the same cached menu can otherwise
be served to different clients within the `CACHE_TTL` window.

Because this depends on the feed's current shape, a breaking change to it can break parsing. If
browsing FilterMusic in LMS starts showing an empty menu or a "could not read the station list" error,
check `FilterMusic/Plugin.pm`'s `_decodeFeed`/`_buildMenu` against the feed's current shape first.

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

**Full-screen Artwork view on Jive/hardware/app clients isn't independently verified.** The server-side
contract for it (`showBigArtwork` plus LMS's own `artwork` CLI command, set in each Artwork item's
`jive` block) is real, confirmed straight from `LMS-Community/slimserver`'s source - but how
SqueezePlay/Jive firmware actually paints that screen, and how Material Skin's client-side JS handles it,
aren't things this repository's source can confirm, since neither firmware nor Material Skin's own repo
was checked. It's confirmed working in the Default web skin (opens the image full-size in a new tab).

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
this plugin, and added the lightweight in-memory cache described above. Version 2.3.0 revisited the
Material Skin background photo's old `wallpapers.json` data source, this time surfacing it as a
browsable Artwork menu item with artist credit rather than an invisible backdrop. Version 2.4.0 made
Artwork items interactive: full-screen viewing and a "Browse Original" link back to an entry's source,
where its credit links to one. See `CHANGELOG.md` for the full detail.

## Credits

FilterMusic.net is created and curated by Spyros. Every station, genre, and image this plugin
displays is their work, not this project's. When I contacted them about reviving the plugin, they
offered immediately to help and built a data feed for it, so it no longer needs to scrape the
website. Thank you, Spyros.

## License

MIT - see `LICENSE`. That covers this plugin's own code; the station data and artwork it reads from
filtermusic.net remain filtermusic.net's own content, not licensed by this project.
