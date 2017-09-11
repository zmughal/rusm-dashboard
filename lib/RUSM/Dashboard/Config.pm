package RUSM::Dashboard::Config;
# ABSTRACT: Configuration

use Moo;
use Function::Parameters;
use Types::Standard qw(HashRef);
use MooX::Lsub;

use Path::Tiny;

use Time::Piece;

has config_data => (
	is => 'ro',
	required => 1,
	isa => HashRef,
);

lsub today => method() {
	Time::Piece->strptime( localtime()->date, "%Y-%m-%d" );
};

lsub current_semester => method() {
	my $today = $self->today;
	my @active_semesters = grep {
		my $start = Time::Piece->strptime( $_->{time}{start}, "%Y-%m-%d" );
		my $end = Time::Piece->strptime( $_->{time}{end}, "%Y-%m-%d" );
		$today >= $start && $today <= $end;
	} @{ $self->config_data->{semester} };

	@active_semesters == 1 or die "Multiple semesters (@{[scalar @active_semesters]})  can not be active at the same time";

	$active_semesters[0];
};

lsub wiki_source_path => method() {
	my $path = path( $self->config_data->{wiki}{source_path} );
	-d $path or die "wiki source path ($path) does not exist";
	$path;
};

lsub wiki_data_path => method() {
	my $path = path($self->config_data->{wiki}{data_path});
	-d $path or die "wiki data path ($path) does not exist";
	path($path);
};

lsub wiki_panopto_path => method() {
	my $path = path($self->config_data->{wiki}{panopto_path});
	-d $path or die "wiki panopto path ($path) does not exist";
	path($path);
};

lsub current_semester_source_path => method() {
	$self->wiki_source_path->child(
		qw(RUSM semester),
		$self->current_semester_name,
	);
};

lsub current_semester_data_path => method() {
	$self->wiki_data_path->child(
		qw(RUSM semester),
		$self->current_semester_name,
	);
};

lsub current_semester_panopto_path => method() {
	$self->wiki_panopto_path->child(
		qw(RUSM semester),
		$self->current_semester_name,
	);
};

lsub current_timezone => method() {
	$self->current_semester->{time}{zone};
};

lsub current_semester_start_date => method() {
	Time::Piece->strptime($self->current_semester->{time}{start}, "%Y-%m-%d" );
};

lsub current_semester_end_date => method() {
	Time::Piece->strptime($self->current_semester->{time}{end}, "%Y-%m-%d" );
};

lsub current_semester_name => method() {
	my $name = $self->current_semester->{name};

	$name =~ /^\w+$/ or die "Semseter name ($name) must not contain spaces";

	$name;
};

1;
