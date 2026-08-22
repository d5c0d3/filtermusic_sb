package Plugins::FilterMusic::Plugin;

#########################################################################
# Plugin: FilterMusic                                                   #
#                                                                       #
# Version: 1.2.0                                                       #
#                                                                       #
# Website: https://filtermusic.net                                     #
#                                                                       #
# Author: d5c0d3 (d5c0d3 at gmail dot com)                      #
#                                                                       #
# Purpose:                                                              #
#  Browse the internet radio stations curated on FilterMusic.net       #
#  from inside Lyrion Music Server / Logitech Media Server, organized  #
#  by the same genre categories used on the site.                      #
#                                                                       #
# Notes on this rewrite (2026):                                        #
#  - filtermusic.net has been rebuilt (Astro) since the plugin was     #
#    first written in 2011; the old accordion markup and RSS feed      #
#    ("Newly Added") are both gone. The whole station list is now      #
#    server-rendered on the front page as <article data-listen=...>    #
#    entries that already carry the direct stream URL, so a single     #
#    fetch of https://filtermusic.net/ is all that's needed.           #
#  - HTML::TreeBuilder (used by the original 0.2 release) is unusable  #
#    on modern LMS: it ships without its HTML::Tagset dependency and   #
#    fails to load (see Logitech/slimserver#594). This version parses  #
#    the markup with plain regexes against LMS core Perl only, so it   #
#    has no risky third-party module dependency.                      #
#########################################################################

use strict;
use warnings;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Cache;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use Plugins::FilterMusic::Settings;

use constant FEED_URL          => 'https://filtermusic.net/';
use constant CACHE_KEY         => 'menu';
use constant CACHE_TTL_MINUTES => 360; # 6 hours - matches the site's "almost daily" update cadence
use constant USER_AGENT        => 'FilterMusic-LMS-Plugin/1.0 (+https://github.com/d5c0d3/filtermusic_sb)';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.filtermusic',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.filtermusic');
my $cache;
my $lastWallpaperCredit = '';

# A small, self-contained entity decoder so we don't depend on HTML::Entities
# (part of the same HTML-Parser CPAN distribution as the HTML::Tagset module
# that's missing from LMS's bundled HTML::TreeBuilder - see notes above).
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

sub getDisplayName { 'PLUGIN_FILTERMUSIC' }

# this ensures the menu is in the radio menu on some player types
sub playerMenu { 'RADIO' }

sub initPlugin {
	my $class = shift;

	$prefs->init({
		cacheTTLMinutes => CACHE_TTL_MINUTES,
		showBackdrop    => 1,
	});

	$cache = Slim::Utils::Cache->new();

	Plugins::FilterMusic::Settings->new;

	# this creates a new menu in the radios menu tree
	$class->SUPER::initPlugin(
		feed   => \&toplevel,
		tag    => 'filtermusic',
		menu   => 'radios',
		is_app => 0,
		weight => 10,
	);
}

sub clearCache {
	$cache->remove(CACHE_KEY) if $cache;
}

sub lastWallpaperCredit { $lastWallpaperCredit }

# this is called every time the user browses into the menu. Unlike the
# station list (cached - see CACHE_TTL_MINUTES), this always does a live
# fetch: filtermusic.net itself only rolls its wallpaper photo on a fresh
# page load, so mirroring that means checking on every visit, not on a
# timer. Browsing *within* FilterMusic (into a category, etc) never calls
# back into the plugin at all - the whole tree below this node is already
# in the response - so the photo naturally stays fixed for that visit and
# only changes the next time this node is entered.
sub toplevel {
	my ($client, $callback, $args) = @_;

	# use server framework for async http fetch
	Slim::Networking::SimpleAsyncHTTP->new(
		# fetch success
		sub {
			my $http = shift;
			_handleFetchedContent($client, $callback, $http->content);
		},

		# fetch failure - fall back to a cached station list (without a
		# fresh photo) rather than failing outright, if we have one
		sub {
			my ($http, $error) = @_;
			$log->warn("error fetching filtermusic.net: $error");

			if ($cache && (my $stations = $cache->get(CACHE_KEY))) {
				$log->debug('serving FilterMusic station list from cache after fetch failure');
				$callback->($stations);
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

sub _handleFetchedContent {
	my ($client, $callback, $content) = @_;

	my $wallpaperUrl;
	if ($prefs->get('showBackdrop')) {
		my ($url, $credit) = _parseWallpaper($content);
		$wallpaperUrl = $url;
		$lastWallpaperCredit = $credit if $url;
	}

	my $stations = $cache ? $cache->get(CACHE_KEY) : undef;

	if ($stations) {
		$log->debug('serving FilterMusic station list from cache');
	}
	else {
		$stations = eval { _parseStations($content) };

		if ($@ || !$stations || !scalar @$stations) {
			$log->error('failed to parse filtermusic.net: ' . ($@ || 'no categories found'));
			$callback->([{
				name => cstring($client, 'PLUGIN_FILTERMUSIC_PARSE_ERROR'),
				type => 'text',
			}]);
			return;
		}

		if ($cache) {
			my $ttl = ($prefs->get('cacheTTLMinutes') || CACHE_TTL_MINUTES) * 60;
			$cache->set(CACHE_KEY, $stations, $ttl);
		}
	}

	$callback->(_withBackdrop($stations, $wallpaperUrl));
}

# Parse the server-rendered accordion markup on filtermusic.net's homepage.
# The site (an Astro static build) emits one <details> block per genre
# category, each containing <article data-title=... data-listen=... ...>
# entries with the direct stream URL already inlined, so no per-station
# page fetch is required.
sub _parseStations {
	my ($content) = @_;

	my @menu;

	while ($content =~ m{<summary>\s*<h2[^>]*>(.*?)</h2>.*?</summary>.*?<div class="accordion-content">(.*?)</div>\s*</div>\s*</div>}gs) {
		my ($rawCategory, $block) = ($1, $2);

		(my $category = $rawCategory) =~ s/<[^>]+>//g;
		$category = _decodeEntities($category);
		$category =~ s/^\s+|\s+$//g;

		my @stations;

		while ($block =~ m{<article class="btn-play\s+radio-info[^"]*"\s+data-title="([^"]*)"\s+data-cast-image="([^"]*)"\s+data-listen="([^"]*)"\s+data-category="([^"]*)"\s+data-nodepath="([^"]*)".*?<p class="text-secondary line-clamp-1">\s*(.*?)\s*</p>}gs) {
			my ($title, $image, $listen, $cat, $nodepath, $desc) = ($1, $2, $3, $4, $5, $6);

			next unless $listen;

			$title = _decodeEntities($title);

			$desc =~ s/<[^>]+>//g;
			$desc = _decodeEntities($desc);

			push @stations, {
				name => length($desc) ? "$title - $desc" : $title,
				type => 'audio',
				url  => _decodeEntities($listen),
				icon => length($image) ? _decodeEntities($image) : undef,
			};
		}

		next unless @stations;

		push @menu, {
			name  => $category,
			items => \@stations,
		};
	}

	return \@menu;
}

# Attach the current visit's wallpaper photo to each category node without
# mutating the (possibly cached) station list itself. Only used by skins
# that render a per-node backdrop from a menu item's own icon (e.g. Material
# Skin, when its "Draw background" setting is on) - every other client
# already ignores unknown fields on a menu node, same as the per-station
# 'icon' set in _parseStations.
sub _withBackdrop {
	my ($menu, $wallpaperUrl) = @_;

	return $menu unless defined $wallpaperUrl;

	return [ map { { %$_, image => $wallpaperUrl } } @$menu ];
}

# filtermusic.net renders a random full-page wallpaper photo (with a credit
# caption) on every homepage load - see the <aside id="wallpaper"> markup.
# We piggyback on the same request used for the station list rather than
# fetching a separate wallpaper feed, so this doesn't add any extra load on
# their server.
sub _parseWallpaper {
	my ($content) = @_;

	my ($url) = $content =~ m{class="wallpaper_container[^"]*"[^>]*style="[^"]*url\((?:&quot;|")([^&"]+)(?:&quot;|")\)}s;
	my ($credit) = $content =~ m{id="wallpaper_credits"[^>]*>([^<]*)<};

	return (undef, undef) unless $url;

	return (_decodeEntities($url), _decodeEntities($credit || ''));
}

1;
