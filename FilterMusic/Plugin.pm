package Plugins::FilterMusic::Plugin;

#########################################################################
# Plugin: FilterMusic                                                   #
#                                                                       #
# Version: 2.4.1                                                       #
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
#  - Artwork menu: an "Artwork" node is appended to the top-level menu #
#    from filtermusic.net's wallpapers.json feed - the same feed the   #
#    Material Skin background-photo feature (added 1.1.0, removed     #
#    1.5.0 - see CHANGELOG.md) used, shown here directly as a          #
#    browsable list of images with their artist/photographer credit   #
#    instead of an invisible, unverifiable backdrop. A failure to      #
#    fetch or parse it never breaks station browsing, which doesn't    #
#    depend on it - see _fetchArtwork.                                 #
#  - Artwork items carry a 'jive' block (see _buildArtworkItem) whose    #
#    only job is a "more" screen - see _artworkInfo/_artworkInfoFeed -  #
#    showing the title/credit, a "Show Artwork" fullscreen action       #
#    (reusing LMS's own 'artwork' CLI command, the same mechanism       #
#    Slim::Menu::TrackInfo/AlbumInfo use), and, when the entry's body   #
#    links to one, a "Browse Original" link to the source. The         #
#    fullscreen action deliberately does NOT live on the primary item  #
#    itself: LMS hoists a 'jive.showBigArtwork' flag there onto every   #
#    JSON-RPC/CLI client's top-level response, and Material Skin's own  #
#    list renderer unconditionally drops any item carrying it,          #
#    emptying the whole list - confirmed against Material's real       #
#    source, and matching real core LMS's own convention (TrackInfo/    #
#    AlbumInfo put "Show Artwork" in the info/"more" menu too, never    #
#    on the primary row). Material has its own native fullscreen+       #
#    next/prev navigation for a plain list of image items anyway, so    #
#    this loses it nothing. The web skin also already opens the image   #
#    full-screen for free from a plain type=>'text' item with an       #
#    image - no jive needed there either.                              #
#########################################################################

use strict;
use warnings;

use base qw(Slim::Plugin::OPMLBased);

use JSON::XS::VersionOneAndTwo;

use Slim::Control::Request;
use Slim::Control::XMLBrowser;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(cstring);

use Plugins::FilterMusic::Settings;

use constant FEED_URL           => 'https://filtermusic.net/stations.json';
use constant WALLPAPER_JSON_URL => 'https://filtermusic.net/wallpapers.json';
use constant WALLPAPER_BASE_URL => 'https://filtermusic.github.io/wallpaper/';
use constant USER_AGENT         => 'FilterMusic-LMS-Plugin/2.0 (+https://github.com/d5c0d3/filtermusic_sb)';
use constant CACHE_TTL          => 300; # seconds

# CLI command name for the artwork "more" info screen (_artworkInfo) - must
# be globally unique across the whole LMS server, hence the plugin-specific
# prefix; FilterMusicDev uses its own distinct name so both plugins can be
# installed side by side without colliding.
use constant ARTWORK_INFO_CMD => 'filtermusicartworkinfo';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.filtermusic',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

my $lastGoodMenu;
my $lastFetchTime  = 0;
my $lastGenerated;

# wallpapers.json has no 'generated' timestamp the way stations.json does,
# so change detection happens per entry instead: %lastArtworkByKey remembers
# each entry's title/credit text, keyed by its field_wallpaper filename (the
# closest thing this feed has to a stable id), alongside the item we built
# from it - see _buildArtworkMenu. An entry whose text is unchanged on the
# next fetch reuses that item rather than re-stripping/re-decoding the same
# credit text again. This doesn't shrink the fetch itself - wallpapers.json
# is one flat array with no way to request only the changed entries - only
# the per-entry rebuild work. $lastArtworkNode is the fallback shown if a
# fetch or parse fails outright, the same "keep the last known good result"
# approach used for $lastGoodMenu above.
my %lastArtworkByKey;
my $lastArtworkNode;

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

	# powers the "more" screen on Artwork items - see _artworkInfo and the
	# 'jive' block built in _buildArtworkItem
	Slim::Control::Request::addDispatch(
		[ ARTWORK_INFO_CMD, 'items', '_index', '_quantity' ],
		[ 0, 1, 1, \&_artworkInfo ],
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

			# station menu is built - now fetch the Artwork submenu before
			# finalizing; a failure there must never hold up or break station
			# browsing, so _fetchArtwork always finalizes either way
			_fetchArtwork($client, $callback, $menu, $feed->{generated});
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

# Fetch filtermusic.net's wallpapers.json feed and, if it decodes to a
# non-empty array, append an "Artwork" node (built by _buildArtworkMenu) to
# the already-built station $menu. Either way, _finalizeMenu is called at
# the end - a fetch or parse failure here falls back to the last known good
# Artwork node (if any) rather than dropping it, since station browsing
# doesn't depend on it either way.
sub _fetchArtwork {
	my ($client, $callback, $menu, $generated) = @_;

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $http = shift;

			my $wallpapers = eval { _decodeWallpapers($http->content) };

			if ($@ || !$wallpapers) {
				$log->error('failed to parse wallpapers.json: ' . ($@ || 'malformed JSON'));
				push @$menu, $lastArtworkNode if $lastArtworkNode;
			} else {
				my $artwork = _buildArtworkMenu($client, $wallpapers);

				if ($artwork) {
					push @$menu, $artwork;
					$lastArtworkNode = $artwork;
				}
			}

			_finalizeMenu($callback, $menu, $generated);
		},

		sub {
			my ($http, $error) = @_;
			$log->error("error fetching filtermusic.net wallpapers.json: $error");
			push @$menu, $lastArtworkNode if $lastArtworkNode;
			_finalizeMenu($callback, $menu, $generated);
		},

		{ timeout => 15 },
	)->get(WALLPAPER_JSON_URL, 'User-Agent' => USER_AGENT);
}

# Decode wallpapers.json's body into a Perl structure and do just enough
# shape validation to fail loudly (caught by the eval in _fetchArtwork).
# Feed shape: [ { title, body, field_wallpaper }, ... ] - body is either an
# HTML string or the JSON boolean false when there's no credit.
sub _decodeWallpapers {
	my ($content) = @_;

	my $wallpapers = decode_json($content);

	die "wallpapers feed is not a JSON array\n" unless ref $wallpapers eq 'ARRAY';
	die "wallpapers feed is empty\n" unless @$wallpapers;

	return $wallpapers;
}

# Turn a decoded wallpapers.json array into a single "Artwork" menu node,
# mirroring _buildMenu's shape. Each item pairs an image with its
# artist/photographer credit (falling back to the title when there's no
# separate credit); entries without a field_wallpaper are skipped.
#
# Change detection is per entry, keyed by field_wallpaper against
# %lastArtworkByKey (see its definition above): an entry whose title/body
# text string-matches what we saw last fetch reuses the item already built
# for it in _buildArtworkItem, instead of re-stripping/re-decoding text
# that hasn't changed.
sub _buildArtworkMenu {
	my ($client, $wallpapers) = @_;

	my @items;
	my %newByKey;

	for my $entry (@$wallpapers) {
		next unless ref $entry eq 'HASH' && length $entry->{field_wallpaper};

		my $key   = $entry->{field_wallpaper};
		my $title = defined $entry->{title} ? $entry->{title} : '';
		# body is a JSON boolean false, not a string, when there's no
		# credit - normalize to a plain string up front so every comparison
		# and regex below is a normal string op, never an operation on a
		# blessed JSON boolean value
		my $body  = $entry->{body} ? "$entry->{body}" : '';

		my $prev = $lastArtworkByKey{$key};
		my $item = ($prev && $prev->{title} eq $title && $prev->{body} eq $body)
			? $prev->{item}
			: _buildArtworkItem($title || $key, WALLPAPER_BASE_URL . $key, $body);

		push @items, $item;
		$newByKey{$key} = { title => $title, body => $body, item => $item };
	}

	%lastArtworkByKey = %newByKey;

	return undef unless @items;

	return {
		name  => cstring($client, 'PLUGIN_FILTERMUSIC_ARTWORK'),
		items => \@items,
	};
}

# Build a single Artwork menu item from one wallpapers.json entry's already
# plain-string title/body (see _buildArtworkMenu). Also pulls out a source
# URL, if the raw body links to one, for the 'more' screen (_artworkInfo) to
# offer as "Browse Original".
sub _buildArtworkItem {
	my ($title, $image, $body) = @_;

	# body's raw markup, before stripping, is the only place a source link
	# lives, e.g. body => '<p><a href="https://...">credit</a></p>' - most
	# entries have no link at all, just plain-text credit
	my ($sourceUrl) = $body =~ /<a\s[^>]*\bhref\s*=\s*"([^"]*)"/i;
	$sourceUrl = _decodeEntities($sourceUrl) if defined $sourceUrl;

	my $credit = length $body ? $body : $title;
	$credit =~ s/<[^>]+>//g;
	$credit =~ s/\s+/ /g;
	$credit =~ s/^\s+|\s+$//g;
	$credit = _decodeEntities($credit);

	# NOT setting 'showBigArtwork'/'actions.do' here - LMS hoists
	# jive.showBigArtwork onto every JSON-RPC/CLI client's top-level response
	# (Slim::Control::XMLBrowser.pm), and Material Skin's own list renderer
	# unconditionally drops any item carrying it (confirmed against its
	# source), silently emptying this whole list. Real core LMS
	# (Slim::Menu::TrackInfo::showArtwork/AlbumInfo::showArtwork) never puts
	# this on a primary browsable row either - it lives on a dedicated
	# "Show Artwork" item inside that row's own info/"more" menu, which is
	# exactly where _artworkInfoFeed puts it below. This also restores
	# Material's own native fullscreen+next/prev navigation for this list,
	# confirmed working before 'jive' existed here at all.
	return {
		name        => ($credit ne '' && $credit ne $title) ? "$title\n$credit" : $title,
		type        => 'text',
		icon        => $image,
		image       => $image,
		description => $credit,
		# offers a "more" screen with the title/credit, a "Show Artwork"
		# fullscreen action, and (when $sourceUrl is set) a "Browse
		# Original" link - see _artworkInfo/_artworkInfoFeed
		jive => {
			actions => {
				more => {
					player => 0,
					cmd    => [ ARTWORK_INFO_CMD, 'items' ],
					params => {
						title  => $title,
						credit => $credit,
						source => (defined $sourceUrl ? $sourceUrl : ''),
						image  => $image,
					},
					window => { isContextMenu => 1 },
				},
			},
		},
	};
}

# Registered via addDispatch in initPlugin - the raw CLI/JSON-RPC command
# handler for the artwork "more" screen. A dispatched command handler
# receives a single $request object, not the ($client, $callback, $args)
# signature OPML feed subs (like toplevel) use - this mirrors
# Slim::Plugin::Podcast::Plugin's showInfo, which bridges the two the same
# way via Slim::Control::XMLBrowser::cliQuery.
sub _artworkInfo {
	my $request = shift;
	Slim::Control::XMLBrowser::cliQuery(ARTWORK_INFO_CMD, \&_artworkInfoFeed, $request);
}

# The "more" screen's actual content, invoked by _artworkInfo above via
# cliQuery using the normal ($client, $callback, $args) feed-sub signature.
# $args->{params} carries the title/credit/source/image that was already
# known when the item was built (see the 'jive' block in _buildArtworkItem),
# so this never needs a network fetch of its own.
sub _artworkInfoFeed {
	my ($client, $callback, $args) = @_;
	my $params = $args->{params} || {};

	my @items;

	# title as its own line only when it says something the credit line
	# doesn't already say (they're often identical - see _buildArtworkItem)
	push @items, { type => 'text', name => $params->{title} }
		if length $params->{title} && $params->{title} ne $params->{credit};
	push @items, { type => 'text', name => $params->{credit} } if length $params->{credit};

	# "Show Artwork" - the fullscreen action, kept off the primary list item
	# (see _buildArtworkItem's comment) and offered here instead, exactly
	# where real core LMS (Slim::Menu::TrackInfo::showArtwork) puts it
	if (length $params->{image}) {
		push @items, {
			type => 'text',
			name => cstring($client, 'SHOW_ARTWORK_SINGLE'),
			jive => {
				actions        => { do => { cmd => [ 'artwork', $params->{image} ] } },
				showBigArtwork => 1,
			},
		};
	}

	if (length $params->{source}) {
		if (Slim::Utils::Misc::canFollowWeblinks($client)) {
			push @items, {
				type    => 'text',
				name    => cstring($client, 'PLUGIN_FILTERMUSIC_ARTWORK_BROWSE_ORIGINAL'),
				weblink => $params->{source},
			};
		} else {
			# this client can't act on a weblink (e.g. real Squeezebox
			# hardware talking SlimProto never sets controllerUA) - show the
			# plain URL as text rather than a dead link
			push @items, { type => 'text', name => $params->{source} };
		}
	}

	$callback->(\@items);
}

sub _finalizeMenu {
	my ($callback, $menu, $generated) = @_;

	$lastGoodMenu  = $menu;
	$lastGenerated = $generated;
	$lastFetchTime = time();
	$callback->($menu);
}

1;
