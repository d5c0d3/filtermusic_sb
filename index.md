# FilterMusic

Browse internet radio stations curated on [FilterMusic.net](https://filtermusic.net) from inside [Lyrion Music Server](https://lyrion.org), organized by genre.

## Features at a glance

#### Browse by genre

House/Dance, Techno/Trance, Jazz, Rock/Metal, Classical, and more — the same categories as filtermusic.net

Needs: nothing

#### Direct playback

Each station plays straight from its stream URL — no extra per-station page fetch

Needs: nothing

#### Station artwork and descriptions

Every entry includes its logo and description, fetched directly from filtermusic.net

Needs: nothing

#### Optional screensaver source

Enable **FilterMusic Screensaver** in Settings to offer filtermusic.net's artwork as a "Server" source for the Image Viewer screensaver on Jivelite-based players (Squeezebox Touch/Radio, SqueezePlay)

Needs: Jivelite-based player

#### Resilient to downtime

If a fetch fails, the plugin falls back to the last successful load instead of showing an empty menu

Needs: nothing

#### Lightly cached

Successful fetches are cached in memory for a few minutes, so repeated browsing doesn't refetch every time

Needs: nothing

#### No risky dependencies

Only uses LMS's own bundled Perl modules — no external dependencies to break

Needs: nothing

## Requirements

*   **Lyrion Music Server 8.0.0+** (tested with Material Skin; classic skin works but doesn't show artwork for radio items)

## Installation

**Via repository (recommended).** In LMS go to **Settings → Plugins → Additional Repositories** and add:

```
https://d5c0d3.github.io/filtermusic_sb/repo.xml
```

Then install **FilterMusic** from the plugin list and restart.

**Manual.** Download the latest `FilterMusic_<version>.zip` from the [releases](https://github.com/d5c0d3/filtermusic_sb/releases), unzip it into your LMS `Plugins/` directory so it sits as `Plugins/FilterMusic/`, and restart:

```
sudo rm -rf /var/lib/squeezeboxserver/Plugins/FilterMusic
sudo unzip FilterMusic_2_3_4.zip -d /var/lib/squeezeboxserver/Plugins/
sudo chown -R squeezeboxserver:nogroup /var/lib/squeezeboxserver/Plugins/FilterMusic
sudo systemctl restart lyrionmusicserver
```

## Quick start

1.  Open **Apps → FilterMusic** in your LMS interface
2.  Browse the genre categories (House/Dance, Techno/Trance, Jazz, etc.)
3.  Select any station to start playing it immediately
4.  Optional: Enable **FilterMusic Screensaver** in Settings for artwork on Jivelite players

## Using it

### Browsing stations

Open **Apps → FilterMusic** and you'll see a list of genre categories matching filtermusic.net's own organization. Each genre contains its curated stations, each with artwork and a description.

Tap any station to play it directly from its stream URL.

### Genre categories

The plugin organizes stations by the same categories as filtermusic.net:

*   House/Dance
*   Techno/Trance
*   Electronica/Industrial
*   Breaks/DrumnBass
*   HipHop/Rap
*   Reggae/Dub/Dancehall
*   Funk/Soul/Disco
*   Lounge Grooves
*   Downtempo/Ambient
*   Various/Mainstream
*   60s/70s/80s/90s
*   Classical
*   Jazz
*   Rock/Metal
*   International/Ethnic

### Screensaver Image Viewer

When **FilterMusic Screensaver** is enabled in Settings, Jivelite-based players (Squeezebox Touch/Radio, SqueezePlay) can use filtermusic.net's artwork as a screensaver source.

On the player, select **FilterMusic Artwork** from the Screensavers picker (When playing / When stopped / When off). This is a separate screensaver entry, not added to Image Viewer's own Sources screen.

**Zoom, rotation, delay, ordering, and caption display** are all controlled by the player itself through its Image Viewer Settings — not by this plugin.

The settings page lists every image's title and photographer/artist credit when the screensaver toggle is on, since most players don't display captions by default.

## Settings reference

Open **Settings → Advanced → FilterMusic** (also linked as **Plugin Settings** at the top of the plugin's page).

| Setting | What it does | Default |
| ------- | ------------ | ------- |
| **FilterMusic Screensaver** | Offer filtermusic.net's artwork as a screensaver source for Jivelite-based players | Off |

## Notes & limitations

*   **Station logos need LMS 9.1.0 or newer.** The feed's logo URLs are WebP images. LMS 9.1.0+ includes a mechanism to handle WebP artwork; on 9.0.3 or older, logos won't display. Upgrade your LMS/Lyrion server to resolve this.
*   **Classic skin doesn't show artwork.** The literally-named "Classic" skin has no artwork support for radio items at all — this is a skin limitation, not a plugin issue.
*   **Storage is in-memory only.** The cached station list and artwork are kept in memory, not persisted to disk. They survive restarts only as long as the cache TTL (5 minutes for stations, 5 minutes for screensaver images).
*   **Feed dependency.** This plugin depends on filtermusic.net's `stations.json` feed. If the feed format changes significantly, parsing may break. The plugin will fall back to the last successful fetch if this happens.

## Credits

FilterMusic.net is created and curated by Spyros. Every station, genre, and image this plugin displays is their work, not this project's. When the original plugin broke due to a site redesign, they offered to help and built a dedicated JSON feed for it.

## License

MIT — see [LICENSE](LICENSE). That covers this plugin's own code; the station data and artwork it reads from filtermusic.net remain filtermusic.net's own content, not licensed by this project.
