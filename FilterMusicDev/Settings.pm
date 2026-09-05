package Plugins::FilterMusicDev::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.filtermusicdev');

sub name { 'PLUGIN_FILTERMUSICDEV' }
sub page { 'plugins/FilterMusicDev/settings/basic.html' }

sub prefs { return ($prefs, 'showInImageViewer') }

1;
