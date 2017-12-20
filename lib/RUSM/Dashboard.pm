package RUSM::Dashboard;
# ABSTRACT: A tool for downloading course materials for Ross University School of Medicine

use Carp::Assert;
use Moo;

use MooX::Role::Logger qw();
use Log::Any::Adapter::Screen qw();
use Log::Any::Adapter ('Screen');

use Function::Parameters;
use MooX::Lsub;
use Try::Tiny;

with qw(MooX::Role::Logger);

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
method password() { $self->_netrc_machine->password; };

lsub _mech => sub {
	my $mech = WWW::Mechanize->new;
	$mech->stack_depth( 0 ); # do not use memory keeping track of history
	$mech;
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
		warn $self->_logger->warn($message) if $retry;

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
		warn $self->_logger->warn("status = $status");

		if ($response->status_line =~ /Can't connect/) {
			$retry++;
			warn $self->_logger->warn("cannot connect...will retry after $retry seconds");
			sleep $retry;
		} elsif ($error_has_occurred_ecollege) {
			$retry++;
			warn $self->_logger->warn("ecollege error...will retry after $retry seconds");
			sleep $retry;
		} elsif ($status == 429) {
			warn $self->_logger->warn("too many requests...ignoring");
			return undef;
		} else {
			warn $self->_logger->warn("something else...");
			$self->_logger->trace( $self->_mech->content );
			return undef;
		}
	}

	warn $self->_logger->warn("giving up...");
	return undef;
}

1;
=head1 DESCRIPTION

This is a tool to download course materials from an online portal to a set of
organised folders. This is meant to be a way to continuously keep up to date
and save time that would be used up in making sure each file is in the correct
directory (e.g., all the material for a given week).

=head1 CONFIGURATION

Add your credentials to your `~/.netrc` file:

  machine rossu.edu
  login FirstNameLastName
  password mypassword

Edit the configuration file in C<example/.rusm.yml> and place in C<~/.rusm.yml>
if you want it to be loaded by default. Otherwise, the path is taken from the
C<--config-file> option.

=cut
