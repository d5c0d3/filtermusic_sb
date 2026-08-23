package Plugins::FilterMusic::Plugin;

#########################################################################
# Plugin: FilterMusic                                                   #
#                                                                       #
# Version: 1.4.0                                                       #
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
#  - There's no persistent cache: every visit to the FilterMusic menu  #
#    fetches and parses filtermusic.net fresh, the same way visiting   #
#    the site itself in a browser loads everything fresh each time.    #
#    Browsing *within* FilterMusic (into a category, a station) never  #
#    calls back into the plugin, since the whole subtree is already in #
#    that response, which is the LMS equivalent of navigating a page   #
#    that's already loaded. The only state kept in memory is the last  #
#    successful result, used purely as a fallback if a fetch fails.    #
#  - The background photo isn't in the homepage HTML at all - the site #
#    picks it client-side (JavaScript, from wallpapers.json) with no   #
#    server-rendered "current" value to scrape. We fetch that same     #
#    JSON list and pick a random entry ourselves instead.              #
#########################################################################

use strict;
use warnings;

use base qw(Slim::Plugin::OPMLBased);

use JSON::XS::VersionOneAndTwo;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use Plugins::FilterMusic::Settings;

use constant FEED_URL           => 'https://filtermusic.net/';
use constant WALLPAPER_JSON_URL => 'https://filtermusic.net/wallpapers.json';
use constant WALLPAPER_BASE_URL => 'https://filtermusic.github.io/wallpaper/';
use constant USER_AGENT         => 'FilterMusic-LMS-Plugin/1.0 (+https://github.com/d5c0d3/filtermusic_sb)';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.filtermusic',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.filtermusic');
my $lastWallpaperCredit = '';
my $lastGoodMenu;

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
		showBackdrop => 1,
	});

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

sub lastWallpaperCredit { $lastWallpaperCredit }

# this is called every time the user browses into the menu
sub toplevel {
	my ($client, $callback, $args) = @_;

	# use server framework for async http fetch
	Slim::Networking::SimpleAsyncHTTP->new(
		# fetch success
		sub {
			my $http = shift;
			my $content = $http->content;

			if ($prefs->get('showBackdrop')) {
				_fetchWallpaper($client, $callback, $content);
			} else {
				_buildMenu($client, $callback, $content, undef);
			}
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

# filtermusic.net's own homepage no longer renders a wallpaper URL into its
# HTML at all - the site instead fetches this same wallpapers.json client-side
# and picks a random entry with JavaScript, on every visitor's own browser,
# auto-rotating on a timer. There's no server-side "current" wallpaper to
# scrape, so we fetch this list ourselves and pick a random entry the same
# way, rather than trying to read a value that was never server-rendered.
sub _fetchWallpaper {
	my ($client, $callback, $content) = @_;

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;

			my $wallpapers = eval { from_json($http->content) };

			if ($@ || ref $wallpapers ne 'ARRAY' || !@$wallpapers) {
				$log->error('failed to parse wallpapers.json: ' . ($@ || 'unexpected format'));
				_buildMenu($client, $callback, $content, undef);
				return;
			}

			my $pick = $wallpapers->[int(rand(scalar @$wallpapers))];
			my $wallpaperUrl;

			if ($pick->{field_wallpaper}) {
				$wallpaperUrl = WALLPAPER_BASE_URL . $pick->{field_wallpaper};

				my $credit = $pick->{body} ? $pick->{body} : ($pick->{title} || '');
				$credit =~ s/<[^>]+>//g;
				$credit =~ s/\s+/ /g;
				$credit =~ s/^\s+|\s+$//g;
				$lastWallpaperCredit = _decodeEntities($credit);
			}

			_buildMenu($client, $callback, $content, $wallpaperUrl);
		},

		# fetch failure here just means no photo for this visit - the station
		# list itself doesn't depend on it
		sub {
			my ($http, $error) = @_;
			$log->error("error fetching filtermusic.net wallpapers.json: $error");
			_buildMenu($client, $callback, $content, undef);
		},

		{ timeout => 15 },
	)->get(WALLPAPER_JSON_URL, 'User-Agent' => USER_AGENT);
}

sub _buildMenu {
	my ($client, $callback, $content, $wallpaperUrl) = @_;

	my $menu = eval { _parseMenu($content, $wallpaperUrl) };

	if ($@ || !$menu || !scalar @$menu) {
		$log->error('failed to parse filtermusic.net: ' . ($@ || 'no categories found'));

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

	$lastGoodMenu = $menu;
	$callback->($menu);
}

# Parse the server-rendered accordion markup on filtermusic.net's homepage.
# The site (an Astro static build) emits one <details> block per genre
# category, each containing <article data-title=... data-listen=... ...>
# entries with the direct stream URL already inlined, so no per-station
# page fetch is required.
sub _parseMenu {
	my ($content, $wallpaperUrl) = @_;

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
			# Only used by skins that render a per-node backdrop from a menu
			# item's own icon (e.g. Material Skin, when its "Draw background"
			# setting is on). Every other client already ignores unknown
			# fields on a menu node, same as the per-station 'icon' above.
			(defined $wallpaperUrl ? (image => $wallpaperUrl) : ()),
		};
	}

	return \@menu;
}

1;
