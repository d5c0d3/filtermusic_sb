package Plugins::FilterMusic::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.filtermusic');

sub name { 'PLUGIN_FILTERMUSIC' }
sub page { 'plugins/FilterMusic/settings/basic.html' }

sub prefs { return ($prefs, 'showInImageViewer') }

1;
