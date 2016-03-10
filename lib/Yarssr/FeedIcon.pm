package Yarssr::FeedIcon;
use Yarssr::Fetcher;

sub new
{
	my $class = shift;
	my $feed = shift;

	my $icondir = $Yarssr::Config::icondir;

	my $self = {
		iconfile	=> $icondir.$feed->get_title.".ico",
		url		=> $feed->get_url,
	};

	bless $self,$class;

	# If we can't load an icon from a file, then try to download one
	# and attempt to load from the file again
	unless ($self->load_icon()) {
		$self->update;
		$self->load_icon;
	}

	return $self;
}

sub get_pixbuf {
	my $self = shift;
	return $self->{'pixbuf'};
}

sub update {
	my $self = shift;

	my ($content,$type) = Yarssr::Fetcher->fetch_icon($self->{'url'});
	open(ICO,'>',$self->{'iconfile'})
		or warn "Could not open icon file: $self->{'iconfile'}\n";

	if ($type ne 'text/html' and $content)
	{
		print ICO $content;
		close(ICO);
	}
	else {
		print ICO "";
		close(ICO);
	}
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
