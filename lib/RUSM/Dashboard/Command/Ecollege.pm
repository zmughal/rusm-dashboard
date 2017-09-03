package RUSM::Dashboard::Command::Ecollege;
# ABSTRACT: Ecollege course material

use feature qw(say);
use Moo;
use Carp::Assert;

use Function::Parameters;
use MooX::Lsub;
use JSON::MaybeXS;

use CLI::Osprey;

lsub _mech => method() { $self->parent_command->_mech };
lsub quicklaunch_ecollege => sub { 'https://myportal.rossu.edu:443/QuickLaunch/api/launch/11'; };

lsub _tree_id_to_course_item_type => sub {
	return +{
		unit => 'CourseUnit',
		contentitem => 'CourseContentItem',
	};
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
	my ($course_item_type, $view_type, $course_item_id) = split "|", $course_link_id;
	# var sessionid = "48308bbc8d"
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

	$self->_mech->follow_link( text_regex => qr/FM 01 Foundations of Medicine 01/ );

	my $course_uri = $self->_course_loading_jsonp_uri;
	$self->_mech->get( $course_uri );
	$self->_mech->follow_link( tag => 'frame', title => qr/Course Header frame/ );

	my $form = $self->_mech->current_form();
	should( $form->attr('id'), 'form1' ) if DEBUG;

	# set action using the JS code
	my ($form_action) = $self->_mech->content =~ qr/f.action\s*=\s*"([^"]+)";/;
	$form->action($form_action);
	$self->_mech->submit;

	# Now on the course page, so look at the course tree
	$self->_mech->follow_link( tag => 'frame', id => 'Tree' );

	my $t = HTML::TreeBuilder->new_from_content( $self->_mech->content );
	$t->look_down( _tag => 'a', class => qr/^(unit|contentitem)/ );


	require Carp::REPL; Carp::REPL->import('repl'); repl();#DEBUG
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
