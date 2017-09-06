package RUSM::Dashboard::Command::Ecollege;
# ABSTRACT: Ecollege course material


use constant RETRY_MAX => 5;

use feature qw(say);
use Moo;
use Carp::Assert;
use Try::Tiny;

use Function::Parameters;
use MooX::Lsub;
use JSON::MaybeXS;

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
		coursehome => 'coursehome',
		managed_upload => 'webuploadcontent',
		managed_threads => 'threadcontent',
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
	my $course_name = $course_a_elem->as_trimmed_text;
	my $course_link = $course_a_elem->attr('href');
	say "Downloading $course_name";

	$self->_mech->follow_link( url => $course_link );

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

method progress_get( $uri ) {
	my $mech = $self->_mech;

	for my $retry (0 .. RETRY_MAX-1) {
		my $message = "Attempting to fetch [ $uri ]";
		$message .= $retry ? " - retry $retry\n" : "\n";
		warn $message;

		$mech->show_progress(1);
		my $response = try {
			$mech->get($uri);
		} catch {
			require Carp::REPL; Carp::REPL->import('repl'); repl();#DEBUG
		};
		$mech->show_progress(0);

		my $success = $response->is_success &&
			$mech->content !~ qr/We are sorry but an error has occurred/;

		return $response if $success;

		my $status = $mech->status;
		warn "status = $status\n";

		if ($response->status_line =~ /Can't connect/) {
			$retry++;
			warn "cannot connect...will retry after $retry seconds\n";
			sleep $retry;
		} elsif ($status == 429) {
			warn "too many requests...ignoring\n";
			return undef;
		} else {
			warn "something else...\n";
			return undef;
		}
	}

	warn "giving up...\n";
	return undef;
}

method fetch_item( $contentitem, $session_id ) {
	say "Fetching $contentitem->{name}";
	$self->_mech->cookie_jar->set_cookie( 0,
		"ActiveItem_${session_id}" => $contentitem->{ecollege_id},
		'/', '.next.ecollege.com',
		undef, 1, undef, undef, 1 );
	if( $contentitem->{ecollege_id} =~ qr/\Q|managed_upload|\E/ ) {
		# do some regular downloading
		if( -d $contentitem->{path} ) {
			say "Already downloaded $contentitem->{name}";
		} else {
			my $response = $self->progress_get( $contentitem->{uri} );
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
		my $response = $self->progress_get( $contentitem->{uri} );
		$self->_mech->save_content($savepath_html);

		# and download all links inside
		say "Finding links";
		my @links = $self->_mech->find_all_links();
		my @download_links;
		my @ignore_links;
		my @not_download_links;
		for my $link (@links) {
			if( $link->URI =~ m,/pub/content/, ) {
				push @download_links, $link;
			} elsif( $link->URI =~ m/\.css$/i ) {
				push @ignore_links, $link;
			} elsif( $link->URI =~ m/^javascript:/ ) {
				push @ignore_links, $link;
			} else {
				push @not_download_links, $link;
			}
		}
		for my $link (@download_links) {
			my $link_filename = [ $link->URI->path_segments ]->[-1];
			my $link_savepath = $savepath_dir->child($link_filename);
			if( -r $link_savepath ) {
				say "Already downloaded @{[ $link->text ]} ($link_filename) for $contentitem->{name}";
			} else {
				my $link_response = $self->progress_get( $link->URI->abs );
				$self->_mech->save_content($link_savepath);
			}
		}
		for my $link (@not_download_links) {
			my $link_filename = [ $link->URI->path_segments ]->[-1];
			say "Not downloading @{[ $link->text ]} (@{[ $link->URI ]}) for $contentitem->{name}";
		}
	}
}

method run() {
	$self->_login;

	$self->_mech->get( 'http://rossuniversity.net/Shared/Portal/ECPWireFrame_xml.asp' );

	my $course_list_tree = HTML::TreeBuilder->new_from_content($self->_mech->content);

	my @mainContentLink = $course_list_tree->look_down(
		_tag => 'a',
		class => 'MainContentLink' );

	for my $course_link (@mainContentLink) {
		say $course_link->as_trimmed_text;
	}

	my ($fm01) = grep {
		$_->as_trimmed_text =~ qr/FM 01 Foundations of Medicine 01/;
	} @mainContentLink;

	$self->download_course( $fm01 );
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
