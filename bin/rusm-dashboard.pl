#!perl
# ABSTRACT: RUSM Dashboard

use FindBin;
use lib "$FindBin::Bin/../lib";
use RUSM::Dashboard;
use utf8::all;

sub main {
	RUSM::Dashboard->new_with_options->run;
}

main;
