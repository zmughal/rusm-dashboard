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

	@active_semesters == 1 or die "A single semester (@{[scalar @active_semesters]}) must be active";

	$active_semesters[0];
};

lsub evalue_path => method() {
	my $path = path( $self->config_data->{path}{evalue} );
	-d $path or die "wiki source path ($path) does not exist";
	$path;
};

lsub ecollege_path => method() {
	my $path = path($self->config_data->{path}{ecollege});
	-d $path or die "wiki ecollege path ($path) does not exist";
	path($path);
};

lsub panopto_path => method() {
	my $path = path($self->config_data->{path}{panopto});
	-d $path or die "wiki panopto path ($path) does not exist";
	path($path);
};

lsub canvas_path => method() {
	my $path = path($self->config_data->{path}{canvas});
	-d $path or die "wiki canvas path ($path) does not exist";
	path($path);
};

lsub current_semester_evalue_path => method() {
	$self->evalue_path->child(
		qw(RUSM semester),
		$self->current_semester_name,
	);
};

lsub current_semester_ecollege_path => method() {
	$self->ecollege_path->child(
		qw(RUSM semester),
		$self->current_semester_name,
	);
};

lsub current_semester_panopto_path => method() {
	$self->panopto_path->child(
		qw(RUSM semester),
		$self->current_semester_name,
	);
};

lsub current_semester_canvas_path => method() {
	$self->canvas_path->child(
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

lsub current_semester_course => method() {
	my $course = $self->current_semester->{course};

	$course =~ /^\w+$/ or die "Semseter name ($course) must not contain spaces";

	$course;
};

1;
