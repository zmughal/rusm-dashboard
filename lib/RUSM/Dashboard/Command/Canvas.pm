package RUSM::Dashboard::Command::Canvas;
# ABSTRACT: Canvas course material

# Canvas API: <https://canvas.instructure.com/doc/api/all_resources.html>

use Moo;
with qw(MooX::Role::Logger);

use Carp::Assert;
use Try::Tiny;
use Function::Parameters;
use MooX::Lsub;

use DateTime;
use DateTime::Format::ISO8601;

use CLI::Osprey;
use JSON::MaybeXS qw(decode_json);
use URI::Encode qw(uri_decode);

use RUSM::Dashboard::IO::Canvas;

lsub io => method() {
	RUSM::Dashboard::IO::Canvas->new(
		config => $self->parent_command->config
	);
};

lsub json_serialize => method() {
	my $json = JSON::MaybeXS->new( canonical => 1 );
};

lsub _mech => method() { $self->parent_command->_mech };
lsub quicklaunch_canvas => sub { 'https://atge.okta.com/home/devryeducationgroup_canvasrossmed_1/0oaan2l42bJbnrzuu0x7/alnan2zsvvOylKx2O0x7?fromHome=true'; };
lsub canvas_domain => sub { 'rossmed.instructure.com' };
lsub canvas_api_endpoint => method() { "https://@{[ $self->canvas_domain ]}/api/v1" };

method _login() {
	$self->parent_command->_login_to_portal;

	$self->_mech->get( $self->quicklaunch_canvas );
	$self->_mech->submit_form;

	$self->_mech->submit_form(
		with_fields => {
			username => $self->parent_command->username,
			password => $self->parent_command->password,
		},
	);

	$self->_mech->submit_form;
}

method api_decode( $data ) {
	return decode_json( $data =~ s/^\Qwhile(1);\E//r )
}

method api_shortcut( $method, @query ) {
	my $uri = URI->new( $self->canvas_api_endpoint );
	$uri->path_segments( $uri->path_segments, @$method );
	$uri->query_form( @query );
	$self->api( $uri );
}

method api( $uri ) {
	$self->_mech->get( $uri );
	$self->api_decode( $self->_mech->content );
}

method courses() {
	# API call:
	# - https://rossmed.instructure.com/api/v1/courses
	$self->api_shortcut( [ 'courses' ] );
}

method course_modules( $course ) {
	my $course_id = $course->{id};
	# API call:
	# - https://rossmed.instructure.com/api/v1/courses/2062/modules
	# - https://rossmed.instructure.com/api/v1/courses/2060/modules
	$self->api_shortcut(  [ qw(courses), ${course_id}, qw(modules) ] );
}

method course_module_items( $module ) {
}

#https://rossmed.instructure.com/api/v1/courses/2062/modules/2571/items
#https://rossmed.instructure.com/api/v1/courses/2062/pages/week-1-lectures-and-materials
#https://rossmed.instructure.com/api/v1/courses/2062/pages/cardiac-muscle-physiology
#https://rossmed.instructure.com/api/v1/courses/2060/modules/2594/items

method links_on_page( $page ) {
	my $tree = HTML::TreeBuilder->new_from_content( $page->{body} );
	my $links = $tree->extract_links;
	my @images = map {
		[ $_->attr('src'), $_ ]
	} @{ [ $tree->find( _tag => 'img' ) ] // [] };

	my @link_item;

	for my $link (@$links, @images) {
		my $url = $link->[0];
		my $element = $link->[1];

		if( $element->attr('data-api-returntype') ) {
			push @link_item, {
				url => uri_decode($element->attr('data-api-endpoint')),
				name => $element->as_trimmed_text,
				type => $element->attr('data-api-returntype'),
			};
		} else {
			push @link_item, {
				url => $url,
				type => 'Other',
			};
		}
	}

	\@link_item;
}

method download_page_recursively( $path, $page ) {
	my $name = $page->{title};
	$self->_logger->info( "Processing page $name" );
	my $page_path = $path->child( $self->io->_name_to_dir($name) );
	$page_path->mkpath;

	my $page_json_save_path = $page_path->child(qw(.archive), "page-@{[ $page->{page_id} ]}.json");
	$page_json_save_path->parent->mkpath;
	$page_json_save_path->spew_utf8( $self->json_serialize->encode( $page ) );

	my $links = $self->links_on_page( $page );
	for my $link (@$links) {
		$self->download_item( $page_path, $link );
	}
}

method download_file( $path, $file ) {
	my $file_json_save_path = $path->child(qw(.archive), "file-@{[ $file->{id} ]}.json" );
	$file_json_save_path->parent->mkpath;
	$file_json_save_path->spew_utf8( $self->json_serialize->encode( $file ) );

	if( -f $path->child($file->{display_name}) ) {
		$self->_logger->trace("Already downloaded @{[ $file->{display_name} ]} @{[ $file->{url} ]}");
		return
	}

	my $response = $self->parent_command->progress_get( $file->{url} );
	die "failed to download $file->{display_name}" unless $response;

	my $savepath = $path->child($response->filename);
	$savepath->parent->mkpath;
	$self->_mech->save_content( $savepath );
}

method download_item( $path, $item ) {
	if( $item->{type} eq 'Page' ) {
		#$self->_logger->info( "Page @{[ $item->{name} ]}" );
		try {
			my $page = $self->api( $item->{url} );
			$self->download_page_recursively( $path, $page );
		} catch {
			warn $self->_logger->error("Could not retrive page @{[ $item->{name} ]}: $_")
		};
	} elsif( $item->{type} eq 'File' ) {
		$self->_logger->info( "File @{[ $item->{name} || $item->{url} ]}" );

		try {
			my $file = $self->api( $item->{url} );
			$self->download_file( $path, $file );
		} catch {
			warn $self->_logger->error("Could not retrive file @{[ $item->{name} ]}: $_")
		};

	} else {
		if( ! defined $item->{url} ) {
			return;
		} elsif( $item->{url} =~ qr/^mailto:/ ) {
			return;
		} elsif( $item->{url} =~ qr|^\Qhttps://rusm.hosted.panopto.com/Panopto/Pages/Embed.aspx\E| ) {
			warn $self->_logger->warn("Can not download Panopto at this time: @{[ $item->{url} ]}");
		} else {
			warn $self->_logger->warn("Not downloading @{[ $item->{url} ]}");
		}
	}
}

method download_course_module_items( $path, $module ) {
	my $items = $self->api( $module->{items_url} );
	for my $item (@$items) {
		my $name = $item->{title};
		$self->_logger->info( "Processing item $name" );
		$self->download_item( $path, $item );
	}
}

method download_course_modules( $path, $course ) {
	my $modules = $self->course_modules( $course );
	for my $module (@$modules) {
		my $name = $module->{name};
		$self->_logger->info( "Processing module $name" );

		my $module_path = $path->child( $self->io->_name_to_dir( $name ) );
		$module_path->mkpath;

		$self->download_course_module_items( $module_path, $module );
	}
}

method current_courses($courses) {
	my $today = DateTime->now;
	my @current_courses = grep {
		# one week before start and one week after end
		my $start_dt = DateTime::Format::ISO8601->parse_datetime($_->{start_at})
			->add( weeks => -1 );
		my $end_dt = DateTime::Format::ISO8601->parse_datetime($_->{end_at})
			->add( weeks => 1 );

		$start_dt <= $today && $today <= $end_dt;
	} @$courses;

	\@current_courses;
}

method run() {
	$self->_logger->trace( "Logging in" );
	$self->_login;

	my $current_courses = $self->current_courses( $self->courses );
	my $top_path = $self->io->path_for_canvas;

	#use Carp::REPL;
	for my $course (@$current_courses) {
		my $name = $course->{name};
		$self->_logger->info( "Processing course $name" );

		my $course_path = $top_path->child( $self->io->_name_to_dir( $name ) );
		$course_path->mkpath;

		$self->download_course_modules( $course_path, $course );
	}
}

1;
