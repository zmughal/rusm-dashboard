package RUSM::Dashboard;

use feature qw(say);
use Carp::Assert;
use Moo;
use Function::Parameters;
use MooX::Lsub;
use HTML::FormatText::Elinks;
use HTML::FormatText;
use HTML::TreeBuilder;

use CLI::Osprey;

use Net::Netrc;
use YAML;
use WWW::Mechanize;

option config_file => (
	is => 'ro',
	format => 's',
	doc => 'Path to configuration file',
	default => sub {
		"$ENV{HOME}/.rusm.yml";
	},
);

lsub config => sub {
	YAML::LoadFile($_[0]->config_file);
};

lsub _netrc_machine => sub { Net::Netrc->lookup('rossu.edu'); };
lsub username => sub { $_[0]->_netrc_machine->login; };
lsub password => sub { $_[0]->_netrc_machine->password; };

lsub _mech => sub {
	WWW::Mechanize->new;
};

has rusm_portal_website => (
	is => 'ro',
	default => 'https://myportal.rossu.edu/',
);


method run() {
}

subcommand evalue => 'RUSM::Dashboard::Command::Evalue';
subcommand ecollege => 'RUSM::Dashboard::Command::Ecollege';

method _login_to_portal() {
	$self->_mech->get($self->rusm_portal_website);
	$self->_mech->submit_form(
		with_fields => {
			map { $_ => $self->$_ } qw(username password)
		}
	);

	should( $self->_mech->title, 'Home - myPortal' ) if DEBUG;
}


lsub quicklaunch_ecollege => sub { 'https://myportal.rossu.edu:443/QuickLaunch/api/launch/11'; };
lsub quicklaunch_panopto => sub { 'https://atge.okta.com/home/adtalemglobaleducation_panoptodmrusm_1/0oafk30rb48lC1dfI0x7/alnfk3ay6o1UBEyIv0x7'; };

1;
