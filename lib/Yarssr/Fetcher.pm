package Yarssr::Fetcher;

use Yarssr::Parser;
use Gtk2;
use MIME::Base64;
use AnyEvent;
use AnyEvent::HTTP;
use URI::URL;

use constant TRUE=>1,FALSE=>0;

sub fetch_feed {
	my ($pkg, $feed) = @_;
	ref $feed eq 'Yarssr::Feed' or die;

	my $login = [$feed->get_username, $feed->get_password];

	Yarssr->log_debug("Downloading " . $feed->get_title . ", " . $feed->get_url);

	return _download($feed->get_url, $login);
}

sub fetch_icon {
	my ($pkg, $url) = @_;
	caller eq 'Yarssr::FeedIcon' or die;

	my $icon_url = URI::URL->new('/favicon.ico', $url);

	if ($icon_url->scheme eq 'http' || $icon_url->scheme eq 'https') {
		return _download($url);
	} else {
		my $cv = AnyEvent::condvar;
		$cv->send({
			content => undef,
			type => undef,
		});
		return $cv;
	}
}

sub fetch_opml {
	my ($pkg, $url) = @_;
	caller eq 'Yarssr::GUI' or die;

	Yarssr->log_debug("Importing OPML from $url");

	return _download($url);
}

sub _download {
	my ($url, $login) = @_;
	caller eq __PACKAGE__ or die;

	my $cv = AnyEvent::condvar;
	my %headers = ('User-Agent' => 'yarssr');

	if ($login->[0] and $login->[1]) {
		$headers{'Authorization'} = "Basic " . MIME::Base64::encode($login->[0] . ':' . $login->[1], '');
	}

	http_get($url,
		headers => \%headers,
		timeout => 60,
		sub {
			my ($data, $headers) = @_;
			Yarssr->log_debug("Fetched: '$url', got status: " . $headers->{Status} . ": " . $headers->{Reason} .
					", type: " . $headers->{"content-type"} . ", " . length $data . " bytes");
			$cv->send({
				content => $headers->{Status} == 200 ? $data : undef,
				type => $headers->{"content-type"},
			});
		}
	);

	return $cv;
}

1;
