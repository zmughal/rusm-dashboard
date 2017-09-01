package RUSM::Dashboard::Command::Evalue;
# ABSTRACT: E-value scheduler

use feature qw(say);
use Moo;
use Carp::Assert;

use Function::Parameters;
use MooX::Lsub;

use CLI::Osprey;

lsub _mech => method() { $self->parent_command->_mech };
lsub quicklaunch_evalue => sub { 'https://myportal.rossu.edu:443/QuickLaunch/api/launch/42'; };

method _login() {
	$self->parent_command->_login_to_portal;


	# Login to E-Value
	$self->_mech->get( $self->quicklaunch_evalue );

	# We are on the E-Value single sign on page.
	should( $self->_mech->title, 'E*Value SSO' ) if DEBUG;

	# Submit the only form on the page (already has the username/password).
	$self->_mech->submit_form();
}

method run() {
	$self->_login;

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
}

1;
