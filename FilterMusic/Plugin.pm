package Plugins::FilterMusic::Plugin;

#########################################################################
# Plugin: FilterMusic                                                   #
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
#########################################################################

use strict;
use warnings;

use base qw(Slim::Plugin::OPMLBased);

use JSON::XS::VersionOneAndTwo;

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::FilterMusic::Settings;

use constant FEED_URL   => 'https://filtermusic.net/stations.json';
use constant USER_AGENT => 'FilterMusic-LMS-Plugin/2.0 (+https://github.com/d5c0d3/filtermusic_sb)';
use constant CACHE_TTL  => 300; # seconds

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.filtermusic',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $lastGoodMenu;
my $lastFetchTime  = 0;
my $lastGenerated;

sub getDisplayName { 'PLUGIN_FILTERMUSIC' }

# this ensures the menu is in the radio menu on some player types
sub playerMenu { 'RADIO' }

sub initPlugin {
	my $class = shift;

	Plugins::FilterMusic::Settings->new;

	# this creates a new menu in the radios menu tree
	# the menu icon itself comes from install.xml's <icon> - Slim::Plugin::OPMLBased
	# does not read an 'icon' key from initPlugin's args, it only ever calls
	# $class->_pluginDataFor('icon'), which is sourced from install.xml
	$class->SUPER::initPlugin(
		feed   => \&toplevel,
		tag    => 'filtermusic',
		menu   => 'radios',
		is_app => 0,
		weight => 10,
	);
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

1;
