package Yarssr::FeedIcon;
use Yarssr::Fetcher;
use File::Slurp;
use AnyEvent;
use URI::URL;

sub new
{
	my $class = shift;
	my $feed = shift;

	my $icondir = $Yarssr::Config::icondir;

	my $self = {
		iconfile    => $icondir.$feed->get_title.".ico",
		feed        => $feed,
	};

	bless $self,$class;

	# If we can't load an icon from a file, then try to download one
	# and attempt to load from the file again
	unless ($self->load_icon()) {
		$self->update;
	}

	return $self;
}

sub get_pixbuf {
	my $self = shift;
	return $self->{'pixbuf'};
}

sub update {
	my $self = shift;

	my $icon_url = $self->{feed}->get_icon_url();
	if ($icon_url) {
		$self->_try_update($icon_url);
	} else {
		my $feed_url = $self->{feed}->get_url();
		$self->_try_update(URI::URL->new('/favicon.ico', $feed_url)->abs, URI::URL->new('/favicon.png', $feed_url)->abs);
	}
}

sub _try_update {
	my ($self, @urls) = @_;
	my $icon_url = shift @urls;
	my $cv = Yarssr::Fetcher->fetch_icon($icon_url);
	$cv->cb(sub {
		my $info = $cv->recv;
		if ($info->{type} ne 'text/html' and $info->{content}) {
			write_file($self->{'iconfile'}, { err_mode => 'carp', atomic => 1, binmode => ':raw' }, $info->{content});
			$self->{feed}->set_icon_url($icon_url);
			$self->load_icon;
		} elsif (scalar @urls) {
			$self->_try_update(@urls);
		} else {
			write_file($self->{'iconfile'}, { err_mode => 'carp', atomic => 1, binmode => ':raw' }, "");
			$self->load_icon;
		}
	});
}

sub load_icon {
	my $self = shift;

	if (! -e $self->{'iconfile'}) {
		$self->{'pixbuf'} = 0;
		return 0;
	}

	my $pixbuf = $self->{'pixbuf'};

	eval {
		$pixbuf = Gtk2::Gdk::Pixbuf->new_from_file($self->{'iconfile'});
		$pixbuf = $pixbuf->scale_simple(16,16,'bilinear')
			if ($pixbuf->get_height != 16);
	};

	$self->{'pixbuf'} = $pixbuf;
	return 1;
}

1;
