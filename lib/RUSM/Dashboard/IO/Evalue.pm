package RUSM::Dashboard::IO::Evalue;
# ABSTRACT: IO for E-value iCalendar files

use Moo;
use MooX::Lsub;
use Function::Parameters;
use Types::Standard qw(InstanceOf);

use Time::Seconds;

has config => (
	is => 'ro',
	isa => InstanceOf['RUSM::Dashboard::Config'],
);

lsub number_of_days_to_lookahead => sub { 10; };
lsub last_day_of_lookahead => method() {
	$self->config->today + $self->number_of_days_to_lookahead * ONE_DAY;
};

lsub evalue_path => method() {
	my $evalue_path = $self->config->current_semester_source_path->child(qw(evalue));
};

lsub ical_data_for_semester => method() {
	my $date = $self->config->current_semester_start_date;
	my $end = $self->config->current_semester_end_date;

	my $ical_data = [];
	while( $date <= $end ) {
		my $date_str = $date->strftime("%Y-%m-%d");

		push @$ical_data, {
			date => $date,
			path => $self->evalue_path->child("${date_str}.ics"),
		};
		$date += ONE_DAY;
	}

	$ical_data;
};


1;
