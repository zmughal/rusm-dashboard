package RUSM::Dashboard::Command::Evalue;
# ABSTRACT: E-value scheduler

use feature qw(say);
use Moo;
with qw(MooX::Role::Logger);

use Carp::Assert;
use Test::Deep::NoTest;

use JSON::MaybeXS;

use Time::Piece;
use Data::ICal;
use Data::ICal::Entry::Event;
use Data::ICal::TimeZone;

use HTML::TreeBuilder;
use HTML::TableExtract;
use String::Strip;

use HTML::FormatText;
use HTML::FormatText::Elinks;

use Function::Parameters;
use MooX::Lsub;

use CLI::Osprey;
use CHI;

use RUSM::Dashboard::IO::Evalue;

option ascii => (
	is => 'ro',
	doc => 'Dump ASCII calendar',
	default => sub { 0 },
);

lsub _cache => method() {
	CHI->new( driver => 'RawMemory', global => 0 );
};
lsub _mech => method() { $self->parent_command->_mech };
lsub quicklaunch_evalue => sub { 'https://myportal.rossu.edu:443/QuickLaunch/api/launch/42'; };

lsub io => method() {
	RUSM::Dashboard::IO::Evalue->new(
		config => $self->parent_command->config
	);
};

lsub _ical_timezone => method() {
	Data::ICal::TimeZone->new(
		timezone => $self->parent_command->config->current_timezone
	);
};

method _login() {
	$self->parent_command->_login_to_portal;

	# Login to E-Value
	$self->_mech->get( $self->quicklaunch_evalue );

	# We are on the E-Value single sign on page.
	should( $self->_mech->title, 'E*Value SSO' ) if DEBUG;

	# Submit the only form on the page (already has the username/password).
	$self->_mech->submit_form();
}

lsub calendar_url => sub {
	URI->new('https://www.e-value.net/index.cfm?FuseAction=users_calendar-main&showPersEvents=1&showConf=1&showSites=1&showShifts=1&showOthPeople=1');
};

method go_to_calendar_frame_page() {
	# Main frame has the important parts of the application.
	$self->_mech->follow_link( id => 'main', tag => 'frame' );

	# Load a URL referenced in the JavaScript.
	my ($main_frame_url) = $self->_mech->content =~ qr/\Qtop.main.location.href = \E"([^"]+)";/;
	$self->_mech->get( $main_frame_url );

	my $show_all_events = $self->calendar_url;
	$self->_mech->get( $self->calendar_url );
}

method year_month_calendar_frame_uri($year, $month) {
	my $ym_uri = $self->calendar_url->clone;
	$ym_uri->query_form(
		$ym_uri->query_form,
		CurntDate => sprintf('%02d/01/%d', $month, $year ),
	);

	$ym_uri;
}

method year_month_calendar_content( $year, $month ) {
	my $content = $self->_cache->compute("year_month_calendar_content-$year-$month", "never", sub {
		$self->_mech->get( $self->year_month_calendar_frame_uri( $year, $month ) );
		$self->_mech->content;
	});
}

has event_uris_for_cal_day => (
	is => 'rw',
	default => sub { +{} },
);

method create_ical_for_date($date) {
	my $cal = Data::ICal->new;
	$cal->add_entry( $self->_ical_timezone->definition );

	my $uris = $self->event_uris_for_cal_day->{$date->year}{$date->mon}{$date->mday};
	for my $uri (@$uris) {
		$self->_mech->get( $uri );

		my $event_uri = $self->_mech->uri;
		my $event_content = $self->_mech->content;

		my $vevent = $self->ical_event_from_event_page( $event_uri, $event_content );

		$cal->add_entry($vevent);
	}

	$cal;
}

method extract_event_links($year, $month) {
	my $calendar_frame_html = $self->year_month_calendar_content( $year, $month );
	my $tree = HTML::TreeBuilder->new_from_content($calendar_frame_html);
	my $calendar_table = $tree->look_down( id => 'calendar-table' );

	my @calDay = $calendar_table->look_down( _tag => 'td', class => qr/^cal(Today)?Day$/ );
	for my $day (@calDay) {
		my $daySpan = $day->look_down( _tag => 'span', class => 'calDayNum' );
		my $mday = $daySpan->as_trimmed_text;

		my @eventElements = $day->look_down( _tag => 'div', class => qr/./ );
		my $event_uris = [];
		for my $event (@eventElements) {
			my $event_a = $event->look_down( _tag => 'a', href => qr/\QFuseAction=ShowEvent\E/ );
			defined $event_a or die "Unexpected: event link was not found in event <div>";
			$event_a->postinsert(['br']);

			push @$event_uris, $event_a->attr('href');
		}
		$self->event_uris_for_cal_day->{$year}{$month}{$mday} = $event_uris;
	}

	# https://www.e-value.net/calendar/index.cfm?user=1225334&LastDate=09/03/2017&FuseAction=ShowCalendar&view=1&categoryid=0&CurntDate=08%2F03%2F2017&MonthChange=Backward&path=&subunitid=6697&conferenceid=0&confcatid=0
	# https://www.e-value.net/calendar/index.cfm?user=1225334&LastDate=09/03/2017&FuseAction=ShowCalendar&view=1&categoryid=0&CurntDate=10%2F03%2F2017&MonthChange=Forward&path=&subunitid=6697&conferenceid=0&confcatid=0,
	# $self->_mech->find_all_links( tag => 'a', url_regex => qr/\QFuseAction=ShowEvent\E/ );
}

method run_ascii() {
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

	my $event_text = "";

	for my $day (@calDay) {
		my $daySpan = $day->look_down( _tag => 'span', class => 'calDayNum' );
		my $mday = $daySpan->as_trimmed_text;

		my @eventElements = $day->look_down( _tag => 'div', class => qr/./ );
		if( @eventElements ) {
			$event_text .= "Day: $mday";
			$event_text .= "\n";
		}
		for my $event (@eventElements) {
			my $event_a = $event->look_down( _tag => 'a', href => qr/\QFuseAction=ShowEvent\E/ );
			defined $event_a or die "Unexpected: event link was not found in event <div>";
			$event_a->postinsert(['br']);

			$event_text .= "\t-----------";
			$event_text .= "\n";
			$event_text .=  join "\n", map { "\t$_" } split "\n", $formatter->format( $event );
			$event_text .= "\n";

			$event_a->replace_with_content()->delete;

			$event->postinsert(['hr']);
		}
	}

	my $formatter_elinks = HTML::FormatText::Elinks->new( input_charset => 'utf-8' );
	say $formatter_elinks->format($calendar_table) =~ s/^References$ .* \Z//xmsr;
	print $event_text;
}

method run_update_ical() {
	my $lookahead_date = $self->io->last_day_of_lookahead;
	my @data_to_download = grep {
		my $ical_data = $_;
		! -r $ical_data->{path}
			||
			(
				$ical_data->{date} >= $self->parent_command->config->today
				&&
				$ical_data->{date} <= $lookahead_date
			)

	} @{ $self->io->ical_data_for_semester };

	my $current_date_to_extract = $data_to_download[0]{date};
	my $last_date_to_extract = $data_to_download[-1]{date};
	while( $current_date_to_extract->mon <= $last_date_to_extract->mon ) {
		$self->extract_event_links( $current_date_to_extract->year, $current_date_to_extract->mon );
		$current_date_to_extract = $current_date_to_extract->add_months(1);
	}

	for my $day_data (@data_to_download) {
		$self->_logger->trace("Downloading events for $day_data->{date}");
		my $cal = $self->create_ical_for_date( $day_data->{date} );
		-d $day_data->{path}->parent || $day_data->{path}->parent->mkpath;
		$day_data->{path}->spew_utf8( $cal->as_string );
	}
}

method run() {
	$self->_login;
	$self->go_to_calendar_frame_page;

	if( $self->ascii ) {
		$self->run_ascii;
	} else {
		$self->run_update_ical;
	}
}

method extract_from_event_page($content) {
	my $te = HTML::TableExtract->new( attribs => { class => 'small' } );
	$te->parse( $content );

	my $tt = ($te->tables)[0]->rows;

	for my $row (@$tt) {
		for my $cell (@$row) {
			next unless defined $cell;
			StripLTSpace($cell);
		}
	}
	+{ map {   $_->[0] =~ s/:$//r, $_->[1]  } grep { $_->[0] } @$tt }
}

method ical_event_from_event_page( $uri, $content ) {
	my $data = $self->extract_from_event_page( $content );

	# Normalise:
	#   Presenters -> Presenter
	if( exists $data->{Presenters} ) {
		$data->{Presenter} = $data->{Presenters};
	}

	my $event_uri = URI->new( $uri );
	my $query_form_hash = { $event_uri->query_form };
	$event_uri->query_form(
		map { $_ => $query_form_hash->{$_} }
		sort qw(FuseAction ESUnique EventType isSess)
	);

	my $uid = "ross-evalue-@{[ $query_form_hash->{ESUnique} ]}";

	# minimum uri: https://www.e-value.net/calendar/index.cfm?FuseAction=ShowEvent&ESUnique=81098003&EventType=2&isSess=1
	# Example:
	# {
	#     Attachments           "",
	#     'Attendance Status'   "Upcoming",
	#     'Event Name'          "CTL Orientation Sessions - CTL: Learning is a Journey",
	#     Location              "CTL - Student Center 3rd Floor",
	#     'Start Date'          "August 31, 2017",
	#     Time                  "2:30 PM - 3:30 PM"
	# }
	assert(
		eq_deeply(
			[ keys %$data ],
			# the only keys we know what to do with
			subsetof('Attachments', 'Attendance Status', 'Event Name', 'Location', 'Start Date', 'Time', 'Presenter', 'Presenters'),
		)
	) if DEBUG;

	# We don't know what do do with this should it not be empty.
	should( $data->{Attachments}, "" ) if DEBUG;

	my ($start_time, $end_time) = map {
		Time::Piece->strptime(
			"$data->{'Start Date'} $_",
			"%B %d, %Y %r"
		)
	} split( /\s*-\s*/, $data->{Time} );

	my $vevent = Data::ICal::Entry::Event->new();

	my $dt_fmt = '%Y%m%dT%H%M%S';
	my $zone = $self->_ical_timezone;
	my $json = JSON::MaybeXS->new;
	$json->canonical(1);

	$vevent->add_properties(
		summary => $data->{'Event Name'},
		location => $data->{Location},
		description => $data->{'Event Name'}
			. ( exists $data->{Presenter} ? " w/ $data->{Presenter}" : "" ),
		( 'x-presenter' => $data->{Presenter} )x!!( exists $data->{Presenter} ),
		uid => $uid,
		url => "$event_uri",
		'x-data-json' => $json->encode($data),
		dtstart => [ $start_time->strftime($dt_fmt), { TZID => $zone->timezone } ],
		dtend   => [ $end_time->strftime($dt_fmt), { TZID => $zone->timezone } ],
	);

	return $vevent;
}


1;
