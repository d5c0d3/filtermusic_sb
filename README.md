# FilterMusic plugin for Lyrion Music Server

Browse the internet radio stations curated on [FilterMusic.net](https://filtermusic.net) from inside
[Lyrion Music Server](https://lyrion.org) (formerly Logitech Media Server / SlimServer), organized by
the same genre categories used on the site (House/Dance, Techno/Trance, Jazz, Rock/Metal, ...).

This repository is both the plugin's source and its self-hosted plugin repository (`repo.xml`), which
GitHub Pages serves at <https://d5c0d3.github.io/filtermusic_sb/repo.xml>.

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
a single request builds the whole menu. The result is cached (`Slim::Utils::Cache`, default 6 hours,
configurable in the plugin's Settings page) so normal browsing doesn't re-fetch the site every time.

Because this depends on filtermusic.net's current HTML structure, a redesign of that site can break
parsing. If browsing FilterMusic in LMS starts showing an empty menu or a "could not read the station
list" error, check `FilterMusic/Plugin.pm`'s `_parseMenu` against the site's current markup first.

## History

The original 0.2 release (2011) scraped an older, jQuery-accordion version of the site using
`HTML::TreeBuilder`. That module's dependencies (`HTML::Tagset`) are not bundled with LMS, so the
0.2 plugin fails to load at all on any reasonably modern server
(see [Logitech/slimserver#594](https://github.com/Logitech/slimserver/issues/594)). Version 1.0.0 is a
full rewrite: no `HTML::TreeBuilder` dependency, updated target versions
(`LogitechMediaServer` 8.0–9.*), response caching, a working Settings page, and parsing rebuilt against
the current filtermusic.net markup. See `CHANGELOG.md` for details.
