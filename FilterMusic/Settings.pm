package Plugins::FilterMusic::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

# Not "use Plugins::FilterMusic::Plugin;" - Plugin.pm itself uses this
# module, and by the time any settings-page request can arrive, LMS has
# already fully loaded Plugin.pm (it's install.xml's <module>), so a plain
# fully-qualified call below resolves fine without a circular use.

my $prefs = preferences('plugin.filtermusic');

sub name { 'PLUGIN_FILTERMUSIC' }
sub page { 'plugins/FilterMusic/settings/basic.html' }

sub prefs { return ($prefs, 'showInImageViewer') }

# Lists each screensaver image's title/credit on the settings page whenever
# the toggle is (or, after this save, will be) on - the only reliable way to
# guarantee credits are visible, since the player's own "Text info" toggle
# that would otherwise show them is off by default and unreachable from the
# server (see Plugin.pm's fetchWallpaperCredits). Overrides the base
# Slim::Web::Settings::handler's synchronous ($class, $client, $paramRef)
# call with the fuller, async-capable signature Slim::Web::HTTP actually
# invokes it with, matching the same pattern Slim::Web::XMLBrowser uses.
sub handler {
	my ($class, $client, $paramRef, $callback, $httpClient, $response) = @_;

	# saveSettings hasn't been processed yet at this point (that happens
	# inside SUPER::handler below), so check the submitted value directly
	# rather than $prefs->get(...) - otherwise credits wouldn't show up
	# until a second page load after just ticking the box and saving
	my $enabled = $paramRef->{saveSettings}
		? $paramRef->{pref_showInImageViewer}
		: $prefs->get('showInImageViewer');

	if ($enabled) {
		Plugins::FilterMusic::Plugin::fetchWallpaperCredits(sub {
			my ($credits) = @_;
			$paramRef->{wallpaperCredits} = $credits;
			my $body = $class->SUPER::handler($client, $paramRef);
			$callback->($client, $paramRef, $body, $httpClient, $response);
		});
		return;
	}

	return $class->SUPER::handler($client, $paramRef);
}

1;
