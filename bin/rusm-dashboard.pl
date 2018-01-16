#!perl
# PODNAME: RUSM Dashboard

use Modern::Perl;

use FindBin;
use lib "$FindBin::Bin/../lib";
use RUSM::Dashboard;
use utf8::all;

use Log::Any::Adapter;

sub main {
	Log::Any::Adapter->set('Screen', min_level => 'trace' );
	RUSM::Dashboard->new_with_options->run;
}

main;
