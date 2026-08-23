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
- **Station artwork** for every entry.
- **Add to Favorites** shortcut from the Settings page, for pinning FilterMusic to your Favorites menu.
- **Resilient to filtermusic.net being down or changing**: if a visit's fetch fails, or the site's
  markup changes enough to break parsing, the plugin falls back to the last successful load instead of
  showing an empty menu or hard error - see "How it works" below.
- **No persistent cache** - every visit is a fresh read of filtermusic.net, so what you see always
  matches the current site (aside from the fallback case above).
- **No risky dependencies** - the original 0.2 release depended on a module LMS doesn't fully bundle
  and failed to load on any current server; this rewrite only uses LMS's own bundled Perl. See
  "History" below.

## Installing

In LMS: **Settings → Plugins → Additional Repositories**, add:

```
https://d5c0d3.github.io/filtermusic_sb/repo.xml
```

The FilterMusic plugin will then appear in the plugin list to install.

## Requirements

- Lyrion Music Server / Logitech Media Server 8.0 or newer.

## How it works

`FilterMusic/Plugin.pm` fetches `https://filtermusic.net/` and parses the server-rendered station
list directly out of the page markup (there is no public API). Each `<article data-listen="...">`
element on the page already carries the direct stream URL, station name, description and artwork, so
a single request builds the whole menu.

There's no persistent cache: every visit to the FilterMusic menu fetches and parses filtermusic.net
fresh, the same way loading the site in a browser loads everything fresh each time. Browsing *within*
FilterMusic (into a category, a station) never calls back into the plugin at all, since the whole
subtree is already in the response for the top-level menu - that's the LMS equivalent of navigating a
page that's already loaded, not a fresh visit. The only state kept in memory is the last successful
result, used purely as a fallback if a fetch ever fails.

Because this depends on filtermusic.net's current HTML structure, a redesign of that site can break
parsing. If browsing FilterMusic in LMS starts showing an empty menu or a "could not read the station
list" error, check `FilterMusic/Plugin.pm`'s `_parseMenu` against the site's current markup first.

## History

The original 0.2 release (2011) scraped an older, jQuery-accordion version of the site using
`HTML::TreeBuilder`. That module's dependencies (`HTML::Tagset`) are not bundled with LMS, so the
0.2 plugin fails to load at all on any reasonably modern server
(see [Logitech/slimserver#594](https://github.com/Logitech/slimserver/issues/594)). Version 1.0.0 was a
full rewrite: no `HTML::TreeBuilder` dependency, updated target versions
(`LogitechMediaServer` 8.0–9.*), a working Settings page, and parsing rebuilt against the current
filtermusic.net markup. Later 1.x releases briefly added (and then removed, after it turned out
unworkable in practice) an optional Material Skin background photo, and simplified the caching approach
down to what's described above. See `CHANGELOG.md` for the full version-by-version detail.

## License

MIT - see `LICENSE`. That covers this plugin's own code; the station data and artwork it reads from
filtermusic.net remain filtermusic.net's own content, not licensed by this project.
