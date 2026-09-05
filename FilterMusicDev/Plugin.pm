package Plugins::FilterMusicDev::Plugin;

#########################################################################
# Plugin: FilterMusic (Dev)                                            #
#                                                                       #
# DEV/TEST BUILD - installs alongside the real FilterMusic plugin,     #
# under its own package/tag/log-category/strings, so it never touches  #
# the real plugin's install or config. See README.md's "Testing a      #
# branch (dev build)" section. Not for release - do not publish this   #
# as the real FilterMusic plugin.                                      #
#                                                                       #
# Version: 2.2.0                                                       #
#                                                                       #
# Website: https://filtermusic.net                                     #
#                                                                       #
# Author: d5c0d3                                                       #
#                                                                       #
# Issues: https://github.com/d5c0d3/filtermusic_sb/issues              #
#                                                                       #
# License: MIT (see LICENSE)                                           #
#                                                                       #
# Purpose:                                                              #
#  Browse the internet radio stations curated on FilterMusic.net       #
#  from inside Lyrion Music Server / Logitech Media Server, organized  #
#  by the same genre categories used on the site.                      #
#                                                                       #
# Notes on this rewrite (2026):                                        #
#  - filtermusic.net now publishes a proper JSON feed at               #
#    https://filtermusic.net/stations.json, regenerated on every site  #
#    deploy, replacing the old approach of scraping the homepage's     #
#    server-rendered accordion markup. One JSON decode replaces the    #
#    HTML/entity regex parsing the original 2026 rewrite needed, and   #
#    nothing here depends on filtermusic.net's markup any more, so a   #
#    site redesign can't quietly break this plugin's parsing.          #
#  - HTML::TreeBuilder (used by the original 0.2 release) is unusable  #
#    on modern LMS: it ships without its HTML::Tagset dependency and   #
#    fails to load (see Logitech/slimserver#594). JSON::XS is bundled  #
#    with LMS core, so this still has no risky third-party dependency. #
#  - Caching: successful fetches are cached in memory for CACHE_TTL    #
#    seconds, so browsing in and back out of the FilterMusic menu a    #
#    few times in a row doesn't refetch every time. Once that TTL      #
#    expires, the feed is still fetched fresh (its `generated`         #
#    timestamp isn't available before the fetch), but if `generated`   #
#    comes back unchanged from the last fetch, the previously-built    #
#    menu is reused rather than rebuilt from scratch. The only state   #
#    kept beyond the TTL window is the last successful result, used as #
#    a fallback if a fetch or parse ever fails.                        #
#  - Screensaver Image Viewer source: when enabled in Settings, the    #
#    plugin's own top-level Jive menu entry gets a `screensavers` key  #
#    added (see initJive) - a real, generic mechanism client firmware  #
#    (Jivelite's SlimMenusApplet.lua) uses to offer that entry's `cmd` #
#    as a selectable "Server" source for the screensaver Image Viewer  #
#    (Jivelite's ImageSourceServer.lua). No existing LMS plugin uses   #
#    this, so it was confirmed by reading ralph-irving/jivelite's own  #
#    source rather than copied from precedent.                        #
#########################################################################

use strict;
use warnings;

use base qw(Slim::Plugin::OPMLBased);

use JSON::XS::VersionOneAndTwo;

use Slim::Control::Jive;
use Slim::Control::Request;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use Plugins::FilterMusicDev::Settings;

use constant FEED_URL              => 'https://filtermusic.net/stations.json';
use constant WALLPAPER_JSON_URL    => 'https://filtermusic.net/wallpapers.json';
use constant WALLPAPER_BASE_URL    => 'https://filtermusic.github.io/wallpaper/';
use constant USER_AGENT            => 'FilterMusicDev-LMS-Plugin/2.0 (+https://github.com/d5c0d3/filtermusic_sb)';
use constant CACHE_TTL             => 300; # seconds
use constant SCREENSAVER_CACHE_TTL => 300; # seconds
use constant SCREENSAVER_CLI_CMD   => 'filtermusicdevartworkscreensaver';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.filtermusicdev',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.filtermusicdev');

# the args initPlugin registers the menu with - kept so a pref change can
# rebuild and re-register the same Jive menu entry (see _updateJiveMenu)
my %pluginArgs = (
	feed   => \&toplevel,
	tag    => 'filtermusicdev',
	menu   => 'radios',
	is_app => 0,
	weight => 10,
);

my $lastGoodMenu;
my $lastFetchTime  = 0;
my $lastGenerated;

my $lastGoodScreensaverImages;
my $lastScreensaverFetchTime = 0;

# wallpapers.json's 'body'/'title' credit text is HTML, e.g. "Die Schlange
# des B. by&nbsp;Nicola Napoli" - decode the handful of entities that
# actually turn up in it rather than pulling in an HTML::Entities dependency
# for this alone.
my %ENTITIES = (
	'amp'   => '&',  'nbsp'  => ' ',  'quot'  => '"',  'apos'  => "'",
	'lt'    => '<',  'gt'    => '>',
	'rsquo' => "\x{2019}", 'lsquo' => "\x{2018}",
	'rdquo' => "\x{201D}", 'ldquo' => "\x{201C}",
	'mdash' => "\x{2014}", 'ndash' => "\x{2013}",
);

sub _decodeEntities {
	my ($str) = @_;
	return '' unless defined $str;
	$str =~ s/&(#(\d+)|#x([0-9a-fA-F]+)|(\w+));/
		defined $2 ? chr($2)
		: defined $3 ? chr(hex($3))
		: exists $ENTITIES{$4} ? $ENTITIES{$4}
		: "&$4;"
	/ge;
	return $str;
}

sub getDisplayName { 'PLUGIN_FILTERMUSICDEV' }

# this ensures the menu is in the radio menu on some player types
sub playerMenu { 'RADIO' }

sub initPlugin {
	my $class = shift;

	Plugins::FilterMusicDev::Settings->new;

	# this creates a new menu in the radios menu tree
	# the menu icon itself comes from install.xml's <icon> - Slim::Plugin::OPMLBased
	# does not read an 'icon' key from initPlugin's args, it only ever calls
	# $class->_pluginDataFor('icon'), which is sourced from install.xml
	$class->SUPER::initPlugin(%pluginArgs);

	Slim::Control::Request::addDispatch(
		[ SCREENSAVER_CLI_CMD ],
		[ 1, 1, 0, \&_artworkScreensaverImages ]
	);

	# registerPluginMenu (called by SUPER::initPlugin above, via initJive) only
	# runs once at startup - re-run it whenever the toggle changes so a running
	# server picks up the new screensavers field without a restart
	$prefs->setChange(sub { $class->_updateJiveMenu }, 'showInImageViewer');
}

# Rebuild and re-register this plugin's top-level Jive menu entry, e.g. after
# the showInImageViewer pref changes. Slim::Control::Jive::registerPluginMenu
# replaces any existing entry with the same 'id' rather than duplicating it.
sub _updateJiveMenu {
	my $class = shift;

	if (my $menu = $class->initJive(%pluginArgs)) {
		Slim::Control::Jive::registerPluginMenu($menu);
	}
}

# Slim::Plugin::OPMLBased::initJive builds this plugin's top-level Jive menu
# entry; add a 'screensavers' field to it when the Settings toggle is on, so
# Jivelite's SlimMenusApplet.lua offers this as a screensaver Image Viewer
# source (see ImageSourceServer.lua / _artworkScreensaverImages below).
sub initJive {
	my ($class, %args) = @_;

	my $menu = $class->SUPER::initJive(%args);

	if ($menu && @$menu && $prefs->get('showInImageViewer')) {
		$menu->[0]{screensavers} = [{
			# already-resolved text, not a stringToken - Jivelite's
			# ScreenSaversApplet.lua displays screensavers[].text verbatim,
			# it does not run it through the client's own string lookup the
			# way the top-level menu's own stringToken/text pair does
			text => cstring(undef, 'PLUGIN_FILTERMUSICDEV_SCREENSAVER'),
			cmd  => [ SCREENSAVER_CLI_CMD ],
		}];
	}

	return $menu;
}

# this is called every time the user browses into the menu
sub toplevel {
	my ($client, $callback, $args) = @_;

	if ($lastGoodMenu && (time() - $lastFetchTime) < CACHE_TTL) {
		$log->debug('serving cached FilterMusic menu (< ' . CACHE_TTL . 's old)');
		$callback->($lastGoodMenu);
		return;
	}

	# use server framework for async http fetch
	Slim::Networking::SimpleAsyncHTTP->new(
		# fetch success
		sub {
			my $http = shift;
			my $content = $http->content;

			my $feed = eval { _decodeFeed($content) };

			if ($@ || !$feed) {
				$log->error('failed to parse filtermusic.net feed: ' . ($@ || 'malformed JSON'));

				if ($lastGoodMenu) {
					$log->debug('serving last known good FilterMusic menu after a parse failure');
					$callback->($lastGoodMenu);
					return;
				}

				$callback->([{
					name => cstring($client, 'PLUGIN_FILTERMUSIC_PARSE_ERROR'),
					type => 'text',
				}]);
				return;
			}

			# the feed is regenerated on every filtermusic.net deploy, not on
			# every request - if its timestamp hasn't moved since our last
			# fetch, the menu we already built from it is still correct, so
			# skip rebuilding it
			if ($lastGoodMenu && defined $feed->{generated} && defined $lastGenerated
				&& $feed->{generated} eq $lastGenerated)
			{
				$log->debug("filtermusic.net feed unchanged since last fetch (generated=$lastGenerated)");
				$lastFetchTime = time();
				$callback->($lastGoodMenu);
				return;
			}

			my $menu = eval { _buildMenu($feed) };

			if ($@ || !$menu || !scalar @$menu) {
				$log->error('failed to build FilterMusic menu: ' . ($@ || 'no genres found'));

				if ($lastGoodMenu) {
					$log->debug('serving last known good FilterMusic menu after a build failure');
					$callback->($lastGoodMenu);
					return;
				}

				$callback->([{
					name => cstring($client, 'PLUGIN_FILTERMUSIC_PARSE_ERROR'),
					type => 'text',
				}]);
				return;
			}

			$lastGoodMenu  = $menu;
			$lastGenerated = $feed->{generated};
			$lastFetchTime = time();
			$callback->($menu);
		},

		# fetch failure - fall back to the last successful result rather than
		# failing outright, if we have one
		sub {
			my ($http, $error) = @_;
			# Not ->warn(): this category's defaultLevel is ERROR, and WARN
			# sits below that threshold in Slim::Utils::Log's severity order
			# (DEBUG < INFO < WARN < ERROR < FATAL) - a warn() here would be
			# silently dropped for anyone who hasn't raised the log level.
			$log->error("error fetching filtermusic.net: $error");

			if ($lastGoodMenu) {
				$log->debug('serving last known good FilterMusic menu after a fetch failure');
				$callback->($lastGoodMenu);
				return;
			}

			$callback->([{
				name => cstring($client, 'PLUGIN_FILTERMUSIC_FETCH_ERROR'),
				type => 'text',
			}]);
		},

		{ timeout => 15 },
	)->get(FEED_URL, 'User-Agent' => USER_AGENT);
}

# Decode the JSON feed body into a Perl structure and do just enough shape
# validation to fail loudly (caught by the eval in toplevel) rather than on
# some deeper, more confusing error. Feed shape:
#   { generated, genres: [ { name, page, stations: [
#       { name, description, page, homepage, stream, playlist, logo } ] } ] }
sub _decodeFeed {
	my ($content) = @_;

	my $feed = decode_json($content);

	die "feed is not a JSON object\n" unless ref $feed eq 'HASH';
	die "feed has no genres array\n" unless ref $feed->{genres} eq 'ARRAY';

	return $feed;
}

# Turn a decoded feed into the menu structure toplevel's callback expects.
sub _buildMenu {
	my ($feed) = @_;

	my @menu;

	for my $genre (@{ $feed->{genres} }) {
		next unless ref $genre eq 'HASH' && ref $genre->{stations} eq 'ARRAY';
		next unless length $genre->{name};

		my @stations;

		for my $station (@{ $genre->{stations} }) {
			next unless ref $station eq 'HASH';
			next unless length $station->{name} && length $station->{stream};

			my $desc = $station->{description};
			my $name = (defined $desc && length $desc) ? "$station->{name} - $desc" : $station->{name};
			my $logo = $station->{logo} || undef;

			push @stations, {
				name        => $name,
				type        => 'audio',
				url         => $station->{stream},
				# both keys point at the same logo: 'icon' drives the menu-list
				# and Jive icon, while 'image' is what XMLBrowser's Now Playing
				# artwork caching (Slim::Control::XMLBrowser, Slim::Web::XMLBrowser)
				# actually reads - it falls back to 'cover'/'icon' in some paths
				# but not the one that seeds a stream's now-playing artwork cache
				icon        => $logo,
				image       => $logo,
				description => (defined $desc && length $desc) ? $desc : undef,
			};
		}

		next unless @stations;

		push @menu, {
			name  => $genre->{name},
			items => \@stations,
		};
	}

	return \@menu;
}

# CLI handler for the 'filtermusicdevartworkscreensaver' command registered
# in initPlugin. Responds with the flat { data => [ {image, caption}, ... ] }
# shape Jivelite's ImageSourceServer.lua expects from a screensaver "Server"
# image source (confirmed against its imgFilesSink, which reads
# chunk.data.data as an array of {image, caption, date, owner}).
sub _artworkScreensaverImages {
	my $request = shift;

	if ($lastGoodScreensaverImages && (time() - $lastScreensaverFetchTime) < SCREENSAVER_CACHE_TTL) {
		$log->debug('serving cached FilterMusic screensaver image list (< ' . SCREENSAVER_CACHE_TTL . 's old)');
		$request->addResult('data', $lastGoodScreensaverImages);
		$request->setStatusDone();
		return;
	}

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;

			my $images = eval { _buildScreensaverImages($http->content) };

			if ($@ || !$images) {
				$log->error('failed to parse wallpapers.json for screensaver: ' . ($@ || 'malformed JSON'));
				$images = $lastGoodScreensaverImages || [];
			} else {
				$lastGoodScreensaverImages = $images;
				$lastScreensaverFetchTime  = time();
			}

			$request->addResult('data', $images);
			$request->setStatusDone();
		},

		sub {
			my ($http, $error) = @_;
			$log->error("error fetching filtermusic.net wallpapers.json for screensaver: $error");
			$request->addResult('data', $lastGoodScreensaverImages || []);
			$request->setStatusDone();
		},

		{ timeout => 15 },
	)->get(WALLPAPER_JSON_URL, 'User-Agent' => USER_AGENT);

	$request->setStatusProcessing() unless $request->isStatusDone();
}

# Decode wallpapers.json and turn it into the flat {image, caption} array
# _artworkScreensaverImages responds with. Feed shape: [ { title, body,
# field_wallpaper }, ... ] - body is either an HTML string or the JSON
# boolean false when there's no credit; entries without a field_wallpaper
# are skipped.
sub _buildScreensaverImages {
	my ($content) = @_;

	my $wallpapers = decode_json($content);

	die "wallpapers feed is not a JSON array\n" unless ref $wallpapers eq 'ARRAY';
	die "wallpapers feed is empty\n" unless @$wallpapers;

	my @images;

	for my $entry (@$wallpapers) {
		next unless ref $entry eq 'HASH' && length $entry->{field_wallpaper};

		my $title = $entry->{title} || $entry->{field_wallpaper};

		# body is a JSON boolean false, not a string, when there's no credit
		my $credit = $entry->{body} ? $entry->{body} : ($entry->{title} || '');
		$credit =~ s/<[^>]+>//g;
		$credit =~ s/\s+/ /g;
		$credit =~ s/^\s+|\s+$//g;
		$credit = _decodeEntities($credit);

		push @images, {
			image   => WALLPAPER_BASE_URL . $entry->{field_wallpaper},
			caption => length($credit) ? $credit : $title,
		};
	}

	return \@images;
}

1;
