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
	$self->_login_to_portal;
}

subcommand evalue => method() {
	$self->_login_to_portal;

	# Login to E-Value
	$self->_mech->get( $self->quicklaunch_evalue );

	# We are on the E-Value single sign on page.
	should( $self->_mech->title, 'E*Value SSO' ) if DEBUG;

	# Submit the only form on the page (already has the username/password).
	$self->_mech->submit_form();

	# Main frame has the important parts of the application.
	$self->_mech->follow_link( id => 'main', tag => 'frame' );

	# Load a URL referenced in the JavaScript.
	my ($main_frame_url) = $self->_mech->content =~ qr/\Qtop.main.location.href = \E"([^"]+)";/;
	$self->_mech->get( $main_frame_url );

	my $show_all_events = 'https://www.e-value.net/index.cfm?FuseAction=users_calendar-main&showPersEvents=1&showConf=1&showSites=1&showShifts=1&showOthPeople=1';
	$self->_mech->get( $show_all_events );

	#say HTML::FormatText::Elinks->format_string();

	my $calendar_frame_html = $self->_mech->content;
	my $tree = HTML::TreeBuilder->new_from_content($calendar_frame_html);
	my $calendar_header = $tree->look_down( _tag => 'div', id => 'calendar-header' );
	my $calendar_month_year = $calendar_header->look_down( _tag => 'h3' );
	say $calendar_month_year->as_trimmed_text;
	my $calendar_table = $tree->look_down( id => 'calendar-table' );

	$calendar_table->attr( border => 1 );
	my @add_event_a = $calendar_table->look_down( href => qr{\Qhttps://www.e-value.net/calendar/index.cfm?fuseaction=addevent\E} );
	for my $add_event_element (@add_event_a) {
		$add_event_element->replace_with_content()->delete;
	}


	my @calDay = $calendar_table->look_down( _tag => 'td', class => qr/^cal(Today)?Day$/ );
	my $formatter = HTML::FormatText->new(leftmargin => 0, rightmargin => 72 );
	for my $day (@calDay) {
		#say $day->as_HTML;
		#use HTML::PrettyPrinter; say join "\n", map { "\t$_" } @{ HTML::PrettyPrinter->new->format($day) };

		my $daySpan = $day->look_down( _tag => 'span', class => 'calDayNum' );
		say "Day: ", $daySpan->as_trimmed_text;

		my @eventElements = $day->look_down( _tag => 'div', class => qr/./ );
		for my $event (@eventElements) {
			my $event_a = $event->look_down( _tag => 'a' );
			$event_a->postinsert(['br']);
			say "<@{[ $event_a->attr('href') ]}>";
			say join "\n", map { "\t$_" } split "\n", $formatter->format( $event );
		}
	}

	my $formatter_elinks = HTML::FormatText::Elinks->new();
	say $formatter_elinks->format($calendar_table) =~ s/^References$ .* \Z//xmsr;
};

method _login_to_portal() {
	$self->_mech->get($self->rusm_portal_website);
	$self->_mech->submit_form(
		with_fields => {
			map { $_ => $self->$_ } qw(username password)
		}
	);

	should( $self->_mech->title, 'Home - myPortal' ) if DEBUG;
}


lsub quicklaunch_evalue => sub { 'https://myportal.rossu.edu:443/QuickLaunch/api/launch/42'; };
lsub quicklaunch_ecollege => sub { 'https://myportal.rossu.edu:443/QuickLaunch/api/launch/11'; };
lsub quicklaunch_panopto => sub { 'https://atge.okta.com/home/adtalemglobaleducation_panoptodmrusm_1/0oafk30rb48lC1dfI0x7/alnfk3ay6o1UBEyIv0x7'; };

1;
