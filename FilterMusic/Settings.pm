package Plugins::FilterMusic::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

use Plugins::FilterMusic::Plugin;

my $prefs = preferences('plugin.filtermusic');

sub name   { 'PLUGIN_FILTERMUSIC' }
sub page   { 'plugins/FilterMusic/settings/basic.html' }
sub prefs  { return ($prefs, qw(cacheTTLMinutes showBackdrop)); }

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'} && $params->{'clearcache'}) {
		Plugins::FilterMusic::Plugin::clearCache();
	}

	# SUPER::handler() (Slim::Web::Settings) saves every name from prefs()
	# unconditionally from $params->{'pref_<name>'} - including when that key
	# is absent, e.g. an unchecked checkbox - so showBackdrop toggling off
	# correctly needs no special-casing here.
	$params->{'filtermusic_wallpaper_credit'} = Plugins::FilterMusic::Plugin::lastWallpaperCredit();

	return $class->SUPER::handler($client, $params);
}

1;
