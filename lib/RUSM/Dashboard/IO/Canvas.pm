package RUSM::Dashboard::IO::Canvas;
# ABSTRACT: I/O for Canvas data

use Moo;
use MooX::Lsub;
use Function::Parameters;
use Types::Standard qw(InstanceOf);

has config => (
	is => 'ro',
	required => 1,
	isa => InstanceOf['RUSM::Dashboard::Config'],
);

method path_for_canvas() {
	$self->config->current_semester_canvas_path->child(qw(canvas));
}

method _name_to_dir( $name ) {
	my $dir_name = $name;
	$dir_name =~ s/\s/_/g;
	$dir_name =~ s/:/__/g;
	$dir_name =~ s,/,-,g;
	return $dir_name;
}

1;
