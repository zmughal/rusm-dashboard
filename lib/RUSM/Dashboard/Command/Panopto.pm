package RUSM::Dashboard::Command::Panopto;
# ABSTRACT: Panopto subcommand

use Moo;
with qw(MooX::Role::Logger);

use Carp::Assert;

use Function::Parameters;
use MooX::Lsub;
use JSON::MaybeXS;

#use SOAP::Lite +trace => [ transport => \&log_message ];
use FindBin;
use lib $FindBin::Bin . '/../vendor/p5-Panopto/lib';
use Panopto;
use Panopto::Folders;
use Panopto::Interface::SessionManagement;

use CLI::Osprey;

use RUSM::Dashboard::IO::Panopto;

use constant VIDEOS_PER_SESSION => 2;

lsub io => method() {
	RUSM::Dashboard::IO::Panopto->new(
		config => $self->parent_command->config
	);
};

lsub _mech => method() { $self->parent_command->_mech };
lsub quicklaunch_panopto => sub { 'https://atge.okta.com/home/adtalemglobaleducation_panoptoclinicalrusm_1/0oagva738q4UdwDSE0x7/alngvadx6fJ6II4kb0x7?fromHome=true'; };
lsub panopto_server => sub { 'rusm.hosted.panopto.com' };
lsub panopto_wsdl => method() { "https://@{[ $self->panopto_server ]}/Panopto/PublicAPISSL/4.2/SessionManagement.svc?wsdl" };
lsub panopto_endpoint => method() { "https://@{[ $self->panopto_server ]}/Panopto/PublicAPISSL/4.2/SessionManagement.svc" };

sub log_message {
	my ($in) = @_;
	if (ref($in) eq "HTTP::Request") {
		# do something...
		use DDP; p $in;
		#print $in->content; # ...for example
	} elsif (ref($in) eq "HTTP::Response") {
		# do something
	}
}

method _login() {
	$self->parent_command->_login_to_portal;

	$self->_mech->get( $self->quicklaunch_panopto );
	$self->_mech->submit_form;

	$self->_mech->submit_form(
		with_fields => {
			username => $self->parent_command->username,
			password => $self->parent_command->password,
		},
	);

	$self->_mech->submit_form;
}

method _get_session_soap_client() {
	my $soap = Panopto::Interface::SessionManagement->new;
	$soap->proxy( $self->panopto_endpoint, cookie_jar => $self->_mech->cookie_jar );

	$soap->autotype(0);
	$soap->want_som(1);

	$soap;
}

method ListFolders(@) {
	my %args = (
		MaxNumberResults => 50,
		PageNumber       => 0,
		ParentFolderId   => undef,
		PublicOnly       => 'false',
		SortBy           => 'Name', # Sessions, Relavance (sic)
		SortIncreasing   => 'true',
		searchQuery      => undef,
		@_,
	);

	my $soap = $self->_get_session_soap_client;

	my $som = $soap->GetFoldersList(
		SOAP::Data->prefix('tns')->name(
			request => \SOAP::Data->value(
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name(
				Pagination => \SOAP::Data->value(
						SOAP::Data->name( MaxNumberResults => $args{'MaxNumberResults'} ),
						SOAP::Data->name( PageNumber => $args{'PageNumber'} ),
					)
				),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( ParentFolderId => $args{'ParentFolderId'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( PublicOnly => $args{'PublicOnly'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( SortBy => $args{'SortBy'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( SortIncreasing => $args{'SortIncreasing'} ),
			),
		),
		SOAP::Data->prefix('tns')->name('searchQuery')->type('string')->value($args{'searchQuery'}),
	);
}

sub ListSessions {
	my $self = shift;
	my %args = (
		MaxNumberResults => 50,
		PageNumber       => 0,
		StartDate        => undef,
		EndDate          => undef,
		FolderId         => undef,
		RemoteRecorderId => undef,
		States           => undef, # Created Scheduled Recording Broadcasting Processing Complete
		SortBy           => 'Name', # Date, Duration State, Relevance
		SortIncreasing   => 'true',
		searchQuery      => undef,
		@_,
	);

	my $soap = $self->_get_session_soap_client;

	my $som = $soap->GetSessionsList(
		SOAP::Data->prefix('tns')->name(
			request => \SOAP::Data->value(
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( EndDate => $args{'EndDate'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( FolderId => $args{'FolderId'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name(
					Pagination => \SOAP::Data->value(
						SOAP::Data->name( MaxNumberResults => $args{'MaxNumberResults'} ),
						SOAP::Data->name( PageNumber => $args{'PageNumber'} ),
					)
				),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( RemoteRecorderId => $args{'RemoteRecorderId'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( SortBy => $args{'SortBy'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( SortIncreasing => $args{'SortIncreasing'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( StartDate => $args{'StartDate'} ),
				SOAP::Data->attr({xmlns => 'http://schemas.datacontract.org/2004/07/Panopto.Server.Services.PublicAPI.V40'})->name( 'States' )->value(
					( $args{'States'} ? \SOAP::Data->value(
						SOAP::Data->name( SessionState => @{$args{'States'}} )
					) : undef ),
				),
			),
		),
		SOAP::Data->prefix('tns')->name('searchQuery')->type('string')->value($args{'searchQuery'}),
	);
}

method GetAllThingsRequest( $method, $result_type, @rest_args ) {
	my @things = ();
	my $total_number_things;
	my $page_number = 0;

	my $downloading = 1;
	do {
		$self->_logger->trace("Downloading $result_type page ${page_number}...");
		my $som = $self->$method( PageNumber => $page_number, @rest_args);
		my $result = $som->result;
		$total_number_things = $result->{TotalNumberResults};
		if( ref $result->{Results} eq 'HASH' and exists $result->{Results}{$result_type} ) {
			push @things, @{ $result->{Results}{$result_type} };
			$self->_logger->trace( "got @{[ scalar @things ]} total of $result_type so far" );
		} else {
			$downloading = 0;
		}
		$page_number++;
	} while( $downloading && @things < $total_number_things );

	\@things;

}

method GetAllFolders() {
	$self->GetAllThingsRequest( 'ListFolders', 'Folder' );
}

method GetAllSessions( @args ) {
	$self->GetAllThingsRequest( 'ListSessions', 'Session', @args );
}

method _make_directory_structure_helper( $folder_hash, $top_folder, $parent_dir ) {
	my $name =  $top_folder->{Name};
	my $dir_name = $self->io->_name_to_dir( $name );
	my $path = $parent_dir->child( $dir_name );

	$top_folder->{path} = $path;

	if( ref $top_folder->{ChildFolders} eq 'HASH' ) {
		for my $child_guid (@{ $top_folder->{ChildFolders}{guid} }) {
			$self->_make_directory_structure_helper(
				$folder_hash,
				$folder_hash->{$child_guid},
				$path,
			);
		}
	}
}

method make_directory_structure( $folder_hash ) {
	my @root_folders = grep { ! defined $_->{ParentFolder}  } values %$folder_hash;
	my $parent_dir = $self->io->path_for_panopto;

	for my $folder (@root_folders) {
		$self->_make_directory_structure_helper(
			$folder_hash,
			$folder,
			$parent_dir,
		)
	}
}

method download_folder( $folder_hash, $folder_guid ) {
	my $top_folder = $folder_hash->{$folder_guid};
	my $folder_path = $top_folder->{path};
	my $folder_json = $folder_path->child( 'folder.json' );

	$self->_logger->info("Looking at folder $folder_path");
	my $sessions_in_folder = $self->ListSessions(
		FolderId => $folder_guid
	)->result;

	my $json = JSON::MaybeXS->new;
	$json->canonical(1);
	$json->allow_blessed(1);

	# Normalise in case the results are an empty string (no results)
	$sessions_in_folder->{Results} ||= {};
	$sessions_in_folder->{Results}{Session} ||= [];

	# normalise if there is only one session
	if( ref $sessions_in_folder->{Results}{Session} ne 'ARRAY' ) {
		$sessions_in_folder->{Results}{Session} = [ $sessions_in_folder->{Results}{Session} ];
	}

	$self->_logger->info( "Number of sessions " . scalar @{ $sessions_in_folder->{Results}{Session} } );
	for my $session (@{ $sessions_in_folder->{Results}{Session} }) {
		my $id = $session->{Id};
		my $name = $session->{Name};
		my $state = $session->{State};
		$self->_logger->info("Session '$name' ($id) (state: $state)");
		next if $state ne 'Complete';

		my $session_path = $folder_path->child( $self->io->_name_to_dir( $name ) );
		my $session_json = $session_path->child( 'delivery.json' );
		if( -f $session_json ) {
			$self->_logger->info( "Session '$name' already downloaded...skipping" );
			next;
		}

		my $tablet_delivery_uri = URI->new("https://@{[ $self->panopto_server ]}/Panopto/PublicAPI/4.1/TabletDeliveryInfo");
		$tablet_delivery_uri->query_form(
			DeliveryId => $id,
			forDownload => 'true',
		);
		$self->_mech->get( $tablet_delivery_uri );
		my $tablet_delivery_data = $json->decode( $self->_mech->content );
		my $stream_data = $tablet_delivery_data->{Delivery}{Streams};

		for my $stream (@$stream_data) {
			my $uri = $stream->{StreamHttpUrl};
			my $tag = $stream->{Tag};
			my $video_path = $session_path->child("$tag.mp4");
			$session_path->mkpath;

			if( ! $uri ) {
				$self->_logger->warn( 'No HTTP stream available. Can not download using HTTP.' );
				$self->_logger->warn( "A StreamUrl is available at: $stream->{StreamUrl}" ) if $stream->{StreamUrl};

				$uri = $stream->{StreamUrl};

				die "Stream is not an .m3u8 $uri" unless $uri =~ qr/\Q.m3u8\E$/;

				my $exit = system(
					qw(ffmpeg -protocol_whitelist), 'file,http,https,tcp,tls,crypto',
					(-i), $stream->{StreamUrl},
					qw(-c copy),
					"$video_path",
				);

				if( $exit != 0 ) {
					$video_path->unlink;
					die "Could not download '$name' to $video_path";
				}
			} else {
				die "Stream is not an .mp4: $uri" unless $uri =~ qr/\Q.mp4\E$/;
				my $response = $self->parent_command->progress_get(
					$uri,
					':content_file' => "$video_path" );
				if( ! $response ) {
					$video_path->unlink;
					die "Could not download '$name' to $video_path";
				}
			}
		}
		$session_json->spew_utf8(
			$json->encode($tablet_delivery_data)
		);
	}

	if( ref $top_folder->{ChildFolders} eq 'HASH' ) {
		for my $child_guid (@{ $top_folder->{ChildFolders}{guid} }) {
			$self->download_folder(
				$folder_hash,
				$child_guid,
			);
		}
	}

	if( -d $folder_path ) {
		$folder_json->spew_utf8(
			$json->encode($top_folder)
		);
	}
}

method run() {
	$self->_logger->trace( "Logging in" );
	$self->_login;
	$self->_logger->info( "Setting server name to @{[ $self->panopto_server ]}" );
	Panopto->SetServerName( $self->panopto_server );

	my $folder_array = $self->GetAllFolders;
	my $folder_hash = +{ map { $_->{Id} => $_ } @$folder_array };
	$self->make_directory_structure($folder_hash);

	for my $folder_guid ( @{ $self->io->panopto_folder_guids } ) {
		$self->download_folder( $folder_hash, $folder_guid );
	}
}

1;
