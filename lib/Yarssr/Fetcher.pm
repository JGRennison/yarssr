package Yarssr::Fetcher;

use Yarssr::Parser;
use Gnome2::VFS (-init);
use Gtk2;

use constant TRUE=>1,FALSE=>0;

sub fetch_feed {
	my ($pkg,$feed) = @_;
	ref $feed eq 'Yarssr::Feed' or die;
	
	my $login = [ $feed->get_username,$feed->get_password ];

	Yarssr->log_debug("Downloading ".$feed->get_title);
	
	my ($content,$error) = _download($feed->get_url,$login);
	if ($content) {
	    return $content;
	}
	else {
		Yarssr->log_debug("failed ($error)");
	   	return 0;
	}
}

sub fetch_icon {
	my ($pkg,$url) = @_;
	caller eq 'Yarssr::FeedIcon' or die;

	my $uri = Gnome2::VFS::URI->new($url);
	
	if ($uri->get_host_name) {
		$url = 'http://'.$uri->get_host_name.'/favicon.ico';
		my ($content,$type) = _download($url);
		return ($content,$type);
	}
	return (0,0);
}

sub fetch_opml {
	my ($pkg,$url) = @_;
	caller eq 'Yarssr::GUI' or die;

	Yarssr->log_debug("Importing OPML from $url");

	my ($content,$type) = _download($url);
	return ($content,$type);
}

sub _download {
	my ($url,$login) = @_;
	caller eq __PACKAGE__ or die;
	
	my ($result, $handle, $info);
	
	my $uri = Gnome2::VFS::URI->new($url);

	if ($login->[0] and $login->[1]) {
		$uri->set_user_name($login->[0]);
		$uri->set_password($login->[1]);
	}

	($result, $handle) = $uri->open('read');
	return (0,$result) unless ($result eq 'ok');
	
	my $bytes_per_iteration = 1024;
	my $content = '';
	
	while ($result eq 'ok') {
		my ($tmp_buffer);
		($result, undef, $tmp_buffer) =
		$handle->read($bytes_per_iteration);

		if ($result eq 'ok') {
		    $content .= $tmp_buffer;
	   	}
		else {
		    last;
		}
	} 

	($result,$info) = $handle->get_file_info('default');
	my $type = $info->get_mime_type;
	
	$result = $handle->close();
	return $content,$type;
}
1;
