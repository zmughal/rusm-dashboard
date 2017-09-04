package RUSM::Dashboard;

use feature qw(say);
use Carp::Assert;
use Moo;
use Function::Parameters;
use MooX::Lsub;

use CLI::Osprey;

use Net::Netrc;
use YAML;
use WWW::Mechanize;

use RUSM::Dashboard::Config;

option config_file => (
	is => 'ro',
	format => 's',
	doc => 'Path to configuration file',
	default => sub {
		"$ENV{HOME}/.rusm.yml";
	},
);

lsub config => method() {
	RUSM::Dashboard::Config->new(
		config_data => YAML::LoadFile($self->config_file),
	);
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

1;
