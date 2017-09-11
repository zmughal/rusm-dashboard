package RUSM::Dashboard;

use feature qw(say);
use Carp::Assert;
use Moo;
use Function::Parameters;
use MooX::Lsub;
use Try::Tiny;

use CLI::Osprey;

use Net::Netrc;
use YAML::XS qw(LoadFile);
use WWW::Mechanize;

use RUSM::Dashboard::Config;

use constant RETRY_MAX => 5;

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
		config_data => LoadFile($self->config_file),
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
subcommand panopto => 'RUSM::Dashboard::Command::Panopto';

method _login_to_portal() {
	$self->_mech->get($self->rusm_portal_website);
	$self->_mech->submit_form(
		with_fields => {
			map { $_ => $self->$_ } qw(username password)
		}
	);

	should( $self->_mech->title, 'Home - myPortal' ) if DEBUG;
}

method progress_get( $uri, @rest ) {
	my $mech = $self->_mech;

	for my $retry (0 .. RETRY_MAX-1) {
		my $message = "Attempting to fetch [ $uri ]";
		$message .= $retry ? " - retry $retry\n" : "\n";
		warn $message;

		$mech->show_progress(1);
		my $response = try {
			$mech->get($uri, @rest);
		} catch {
			require Carp::REPL; Carp::REPL->import('repl'); repl();#DEBUG
		};
		$mech->show_progress(0);

		my $error_has_occurred_ecollege = $mech->content =~ qr/We are sorry but an error has occurred/s;

		my $success = $response->is_success && ! $error_has_occurred_ecollege;

		return $response if $success;

		my $status = $mech->status;
		warn "status = $status\n";

		if ($response->status_line =~ /Can't connect/) {
			$retry++;
			warn "cannot connect...will retry after $retry seconds\n";
			sleep $retry;
		} elsif ($error_has_occurred_ecollege) {
			$retry++;
			warn "ecollege error...will retry after $retry seconds\n";
			sleep $retry;
		} elsif ($status == 429) {
			warn "too many requests...ignoring\n";
			return undef;
		} else {
			warn "something else...\n";
			say $self->_mech->content;
			return undef;
		}
	}

	warn "giving up...\n";
	return undef;
}

1;
