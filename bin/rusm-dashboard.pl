#!perl
# ABSTRACT: RUSM Dashboard

use FindBin;
use lib "$FindBin::Bin/../lib";
use RUSM::Dashboard;

sub main {
	RUSM::Dashboard->new_with_options->run;
}

main;
