package RUSM::Dashboard::IO::Ecollege;
# ABSTRACT: I/O for Ecollege data

use Moo;
use MooX::Lsub;
use Function::Parameters;
use Types::Standard qw(InstanceOf);

has config => (
	is => 'ro',
	required => 1,
	isa => InstanceOf['RUSM::Dashboard::Config'],
);

method path_for_ecollege() {
	$self->config->current_semester_ecollege_path->child(qw(ecollege));
}

method _name_to_dir( $name ) {
	my $dir_name = $name;
	$dir_name =~ s/\s/_/g;
	$dir_name =~ s/:/__/g;
	$dir_name =~ s,/,-,g;
	return $dir_name;
}

method path_for_course( $course_data ) {
	my $course_dir_name = $self->_name_to_dir($course_data->{name});
	$self->path_for_ecollege->child($course_dir_name);
}

method path_for_unit( $unit_data, $course_data ) {
	my $unit_dir_name = $self->_name_to_dir($unit_data->{name});
	$course_data->{path}->child( $unit_dir_name );
}

method path_for_contentitem( $contentitem_data, $unit_data ) {
	my $contentitem_dir_name = $self->_name_to_dir($contentitem_data->{name});
	$unit_data->{path}->child( $contentitem_dir_name );
}

method path_for_contentitem_original( $unit_data, $course_data ) {
}

method path_for_contentitem_modified( $unit_data, $course_data ) {
}

1;
