package RUSM::Dashboard::Command::Ecollege;
# ABSTRACT: Ecollege course material

use Moo;
with qw(MooX::Role::Logger);

use Carp::Assert;
use Try::Tiny;

use Function::Parameters;
use List::AllUtils qw(pairgrep pairvalues);
use MooX::Lsub;
use JSON::MaybeXS;
use WWW::Mechanize::Link;

use CLI::Osprey;

use RUSM::Dashboard::IO::Ecollege;

lsub io => method() {
	RUSM::Dashboard::IO::Ecollege->new(
		config => $self->parent_command->config
	);
};

lsub _mech => method() { $self->parent_command->_mech };
lsub quicklaunch_ecollege => sub { 'https://myportal.rossu.edu:443/QuickLaunch/api/launch/11'; };

lsub _tree_id_to_course_item_type => sub {
	return +{
		unit => 'CourseUnit',
		contentitem => 'CourseContentItem',
	};
};

lsub _course_item_type_class_qr => method() {
	my $intersection = join "|", map { "\Q$_\E" } %{ $self->_tree_id_to_course_item_type };
	return qr/^($intersection)/;
};

lsub _view_type_id_to_subdomain => sub {
	return +{
		managed_html => 'vizedhtmlcontent',
		html => 'vizedhtmlcontent',
		managed_od => 'msofficecontent',
		coursehome => 'coursehome',
		managed_upload => 'webuploadcontent',
		managed_threads => 'threadcontent',
		thread => 'threadcontent',
		studentexam_v6 => 'takeexam',
	};
};

method course_item_to_html_render_uri($course_link_id, $session_id) {
	my ($course_item_type, $view_type, $course_item_id) = split /\Q|\E/, $course_link_id;
	exists $self->_tree_id_to_course_item_type->{ $course_item_type }
		or die "could not find contentitem for $course_item_type" if DEBUG;

	exists $self->_view_type_id_to_subdomain->{ $view_type }
		or die "could not find subdomain for $view_type" if DEBUG;

	my $domain =  $self->_view_type_id_to_subdomain->{ $view_type } . ".next.ecollege.com";
	my $uri = URI->new("http://${domain}/(NEXT(${session_id}))/default/Launch.ed");

	$uri->query_form(
		courseItemSubId => $course_item_id,
		courseItemType => $self->_tree_id_to_course_item_type->{ $course_item_type }
	);

	$uri;
}

method _login() {
	$self->parent_command->_login_to_portal;

	my $mech = $self->parent_command->_mech;

	# Login to Ecollege
	$mech->get( $self->quicklaunch_ecollege );

	# We are on the Ecollege single sign on page.
	should( $mech->title, 'ecollege' ) if DEBUG;

	$self->_mech->submit_form();
}

method download_course( $course_a_elem ) {
	my $course_name = $course_a_elem->text;
	my $course_link = $course_a_elem->URI->abs;
	$self->_logger->info( "Downloading $course_name" );

	$self->_mech->get( $course_link );

	if($self->_mech->content =~ qr/\QThis is not an active course.\E/) {
		$self->_logger->notice("$course_name is not an active course");
		return;
	}

	my $course_uri = $self->_course_loading_jsonp_uri;
	$self->_mech->get( $course_uri );
	$self->_mech->follow_link( tag => 'frame' ); # title => qr/Course Header frame/

	my $form = $self->_mech->current_form();
	should( $form->attr('id'), 'form1' ) if DEBUG;

	# set action using the JS code
	my ($form_action) = $self->_mech->content =~ qr/f.action\s*=\s*"([^"]+)";/;
	$form->action($form_action);
	$self->_mech->submit;

	# Now on the course page, so look at the course tree
	$self->_mech->follow_link( tag => 'frame', id => 'Tree' );

	my ($session_id) = $self->_mech->content =~ /var sessionid = "([^"]+)"/;

	my $t = HTML::TreeBuilder->new_from_content( $self->_mech->content );

	my $course_data = {
		_element => $course_a_elem,
		type => 'course',
		name => $course_name,
		children => [],
	};
	$course_data->{path} = $self->io->path_for_course($course_data);

	my @course_item_els = $t->look_down( _tag => 'a', class => $self->_course_item_type_class_qr );
	my $current_unit_data = undef;
	my $current_contentitem_ctr = 1;
	for my $course_item_el (@course_item_els) {
		if( $course_item_el->attr('class') =~ /^unit/ ) {
			$current_unit_data = {
				_element => $course_item_el,
				type => 'unit',
				name => $course_item_el->as_trimmed_text,
			};
			$current_unit_data->{path} = $self->io->path_for_unit( $current_unit_data, $course_data );

			push @{ $course_data->{children} }, $current_unit_data;
			$current_contentitem_ctr = 1;
		} elsif( $course_item_el->attr('class') =~ /^contentitem/ ) {
			my $contentitem_data = {
				_element => $course_item_el,
				type => 'contentitem',
				name => sprintf("%02d", $current_contentitem_ctr) . "_" . $course_item_el->as_trimmed_text,
			};
			$contentitem_data->{path} = $self->io->path_for_contentitem( $contentitem_data, $current_unit_data );

			push @{ $current_unit_data->{children} }, $contentitem_data;
			$current_contentitem_ctr++;
		} else {
			die "Unknown course item type for @{[ $course_item_el->attr('class') ]}";
		}
	}
	use Data::Rmap qw(rmap_hash);
	rmap_hash {
		if(exists $_->{_element}) {
			$_->{ecollege_id} = $_->{_element}->attr('id');
			$_->{uri} = $self->course_item_to_html_render_uri( $_->{ecollege_id}, $session_id );
		}
	} $course_data->{children};

	rmap_hash {
		if(exists $_->{uri}) {
			try {
				$self->fetch_item( $_, $session_id );
			} catch {
				require Carp::REPL; Carp::REPL->import('repl'); repl();#DEBUG
			};
		}
	} $course_data;
}

method fetch_item( $contentitem, $session_id ) {
	$self->_logger->info("Fetching $contentitem->{name}");
	$self->_mech->cookie_jar->set_cookie( 0,
		"ActiveItem_${session_id}" => $contentitem->{ecollege_id},
		'/', '.next.ecollege.com',
		undef, 1, undef, undef, 1 );
	if( $contentitem->{ecollege_id} =~ qr/\Q|\E(managed_upload|managed_od)\Q|\E/ ) {
		# do some regular downloading
		if( -d $contentitem->{path} ) {
			$self->_logger->info("Already downloaded $contentitem->{name}");
		} else {
			my $response = $self->parent_command->progress_get( $contentitem->{uri} );
			die "failed to download $contentitem->{name}" unless $response;
			my $savepath = $contentitem->{path}->child($response->filename);
			$savepath->parent->mkpath;
			$self->_mech->save_content( $savepath );
		}
	} else {
		my $savepath_dir = $contentitem->{path};
		$savepath_dir->mkpath;

		my $savepath_html = $savepath_dir->child(qw(.archive index.html));
		$savepath_html->parent->mkpath;

		# do some html downloading
		my $response = $self->parent_command->progress_get( $contentitem->{uri} );
		die "failed to download $contentitem->{name}" unless $response;
		my $modify_content = $self->_mech->content;
		$modify_content =~ s|Welcome .* ,  There are no new items since .*$||gm;
		$modify_content =~ s|\Q<TD align="right">\ELast Login:[^<]*\Q</TD>\E||gmi;
		my $tree = HTML::TreeBuilder->new_from_content( $modify_content  );
		for my $script ($tree->look_down( _tag => 'script', type => 'text/javascript' ) ) {
			$script->delete;
		}
		for my $head ( $tree->look_down( _tag => 'head' ) ) {
			for my $link ($head->look_down( _tag => 'link', rel => 'stylesheet' ) ) {
				$link->delete;
			}
		}
		for my $input ( $tree->look_down( _tag => 'input', id => qr/(activeSessionId|^encrypted|^GoldenTicket|__VIEWSTATEGENERATOR)/ )  ) {
			$input->delete;
		}
		for my $form ( $tree->look_down( _tag => 'form', action => qr/(^ListThreadsView_V2)/ )  ) {
			$form->delete;
		}
		$self->_mech->update_html( $tree->as_HTML );
		$self->_mech->save_content($savepath_html);

		# and download all links inside
		$self->_logger->trace( "Finding links" );
		my @links = ($self->_mech->links(), $self->_mech->images());
		my @download_links;
		my @ignore_links;
		my @not_download_links;
		for my $link (@links) {
			if( $link->url_abs !~ m|^https?://| ) {
				# skip non-HTTP URIs such as mailto:
				push @ignore_links, $link;
			} elsif( $link->URI =~ m,/pub/content/, ) {
				push @download_links, $link;
			} elsif( $link->URI =~ m/\Q.css\E$/i ) {
				push @ignore_links, $link;
			} elsif( $link->URI eq '#' ) {
				push @ignore_links, $link;
			} else {
				push @not_download_links, $link;
			}
		}
		my $get_text = fun($link) {
			$link->can('text') ? ($link->text // '') : '';
		};
		for my $link (@download_links) {
			my $link_filename = [ $link->URI->path_segments ]->[-1];
			my $link_savepath = $savepath_dir->child($link_filename);
			if( -r $link_savepath ) {
				$self->_logger->info( "Already downloaded @{[ $link->$get_text()  ]} ($link_filename) for $contentitem->{name}" );
			} else {
				my $link_response = $self->parent_command->progress_get( $link->URI->abs );
				die $self->_logger->error("failed to download @{[ $link->$get_text() ]}") unless $link_response;
				$self->_mech->save_content($link_savepath);
			}
		}
		for my $link (@not_download_links) {
			$self->_logger->info("Not downloading @{[ $link->$get_text() ]} (@{[ $link->URI ]}) for $contentitem->{name}");
		}
	}
}

method run() {
	$self->_login;

	$self->_mech->get( 'http://rossuniversity.net/Shared/Portal/ECPWireFrame_xml.asp' );

	my $tree = HTML::TreeBuilder->new_from_content($self->_mech->content);
	my %semesters = map { $_->as_trimmed_text => $_ } $tree->look_down( _tag => 'tr', class => 'MainContentSubHeadBg' );
	my $start_time = $self->parent_command->config->current_semester_start_date->strftime("%B %Y");
	my @current_semesters = pairvalues pairgrep { $a =~ /\Q$start_time\E/ } %semesters;

	my @mainContentLink;
	for my $semester (@current_semesters) {
		my $next_sibling = ($current_semesters[0]->right())[0];
		push @mainContentLink,
			map {
				WWW::Mechanize::Link->new( {
					url  => $_->[0],
					text => $_->[1]->as_trimmed_text,
					tag  => $_->[3],
					base => $self->_mech->uri,
				});
			}
			grep { $_->[1]->attr('class') eq "MainContentLink" }
			@{ $next_sibling->extract_links }
	}

	$self->_logger->info( "Courses:" ) if @mainContentLink;
	for my $course_link (@mainContentLink) {
		$self->_logger->info( "\t" . $course_link->text );
	}

	for my $course_link (@mainContentLink) {
		$self->_logger->info( $course_link->text );
		$self->download_course( $course_link );
	}

}

method _course_loading_jsonp_uri() {
	my $course_callback = $self->_course_loading_data;
	$self->_mech->get( $course_callback );

	my $jsonp = $self->_mech->content;
	my ($jsonp_data) = $jsonp =~ /^jsonp\d*\((.*)\);$/;
	my $json = decode_json( $jsonp_data );

	assert( ! $json->{error} ) if DEBUG;
	return "http://rossuniversity.net/re/DotNextLaunch.asp"
		. $json->{parms} . $json->{macid};
}

method _course_loading_data() {
	my $course_connect_tree = HTML::TreeBuilder->new_from_content($self->_mech->content);
	my $token = $course_connect_tree->look_down(
		_tag => 'input',
		id => 'token' )->attr('value');
	my $site  = $course_connect_tree->look_down(
		_tag => 'input',
		id => 'site' )->attr('value');

	my ($callback) = $course_connect_tree->as_HTML =~ qr/callback:\s*"(jsonp[^"]*)"/;


	my $course_callback_loading_uri = $self->_mech->uri;
	my $course_callback = URI->new($site);
	$course_callback->path("/Main/JsonMode/JsonSession/JsonInitSession.ed");
	$course_callback->query_form( token => $token, callback => $callback );

	$course_callback;
}


1;
