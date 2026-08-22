package Plugins::FilterMusic::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

use Plugins::FilterMusic::Plugin;

my $prefs = preferences('plugin.filtermusic');

sub name   { 'PLUGIN_FILTERMUSIC' }
sub page   { 'plugins/FilterMusic/settings/basic.html' }
sub prefs  { return ($prefs, qw(cacheTTLMinutes)); }

sub handler {
	my ($class, $client, $params) = @_;

	if ($params->{'saveSettings'} && $params->{'clearcache'}) {
		Plugins::FilterMusic::Plugin::clearCache();
	}

	return $class->SUPER::handler($client, $params);
}

1;
