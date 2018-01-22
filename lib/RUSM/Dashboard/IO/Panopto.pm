package RUSM::Dashboard::IO::Panopto;
# ABSTRACT: I/O for Panopto data

use Moo;
use MooX::Lsub;
use Function::Parameters;
use Types::Standard qw(InstanceOf);

has config => (
	is => 'ro',
	required => 1,
	isa => InstanceOf['RUSM::Dashboard::Config'],
);

method path_for_panopto() {
	$self->config->current_semester_panopto_path->child(qw(panopto));
}

method _name_to_dir( $name ) {
	my $dir_name = $name;
	$dir_name =~ s/\s/_/g;
	$dir_name =~ s/:/__/g;
	$dir_name =~ s,/,-,g;
	return $dir_name;
}

method panopto_folder_guids() {
	$self->config->current_semester->{panopto}{folders};
}

1;
