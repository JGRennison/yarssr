package Yarssr;

use Gnome2;
use Gtk2;
use Yarssr::GUI;
use Yarssr::Config;
use Locale::gettext;
use POSIX qw/setlocale/;
use base 'Exporter';

use vars qw(
	$LIBDIR		$PREFIX		$NAME	$VERSION
	$AUTHOR		@CO_AUTHORS	$URL	$LICENSE);

our $NAME		= 'yarssr';
our $VERSION	= '0.2.2';
our $LICENSE	= 'GNU General Public License (GPL)';
our $URL		= 'http://yarssr.sf.net';
our $AUTHOR		= "Lee Aylward";
our @COAUTHORS	= ( "James Curbo","Dan Leski" );
our @TESTERS	= (	"Thanks to Joachim Breitner for testing\n".
					"and maintaining the Debian package");
our $debug = 0;
our @EXPORT_OK = qw(_);

my $feeds = ();
$0 = $NAME;

sub init {
	# il8n stuff
	my $locale = (defined($ENV{LC_MESSAGES}) ? $ENV{LC_MESSAGES} : $ENV{LANG});
	setlocale(LC_ALL, $locale);
	bindtextdomain(lc($NAME), sprintf('%s/share/locale', $PREFIX));
	textdomain(lc($NAME));

	# Wait 2 seconds before loading config and begining downloads
	Gnome2::Program->init($0,$VERSION);
	Glib::Timeout->add(1000,\&initial_launch);
	Yarssr::Config->init;
	Yarssr::GUI->init;
}

sub quit {
	Yarssr::Config->quit;
	Yarssr::GUI->quit;
}

sub log_debug {
	return unless $debug;
	my ($sec,$min,$hour,undef) = localtime;
	my $time = sprintf("%02d:%02d:%02d",$hour,$min,$sec);
	print STDERR "[$time] $_[1]\n" if -t;
}


sub initial_launch {
	Yarssr::Config->load_initial_state;
	Glib::Timeout->add(300, sub { 1 });

	if (Yarssr::Config->get_startonline) {
		download_all();
	}
	else {
		Yarssr::GUI->redraw_menu;
	}

	return 0;
}

sub add_feed {
	my (undef,$feed)  = @_;
	ref $feed eq 'Yarssr::Feed' or die;

	return 0 if (Yarssr->get_feed_by_url($feed->get_url) and
		Yarssr->get_feed_by_title($feed->get_title));

	push @feeds,$feed;
	@feeds = sort {
		lc $a->get_title cmp lc $b->get_title} @feeds;
	return 1;
}

sub get_feeds_array
{
	return @feeds;
}

sub download_feed
{
	my (undef,$feed) = @_;
	$feed->update;
}

sub download_all
{
	Yarssr::GUI->set_icon_active;
	for my $feed (@feeds) {
		Yarssr::GUI->gui_update;
		$feed->update if $feed->get_enabled;
	}
	Yarssr::GUI->redraw_menu;
	Yarssr::Config->write_states;
	return 1;
}

sub get_feed_by_url {
	my (undef,$url) = @_;
	for (@feeds) {
		return $_ if $_->get_url eq $url;
	}
	return 0;
}

sub get_feed_by_title {
	my (undef,$title) = @_;
	for (@feeds) {
		return $_ if $_->get_title eq $title;
	}
	return 0;
}

sub remove_feed {
	my (undef,$feed) = @_;
	die unless ref $feed eq 'Yarssr::Feed';
	for (0 .. $#feeds) {
		if ($feeds[$_]->get_title eq $feed->get_title) {
			splice @feeds,$_,1;
			$feed = undef;
			last;
		}
	}
}

sub get_total_newitems {
	my $newitems = 0;
	for (@feeds) {
	$newitems += $_->get_newitems;
	}
	return $newitems;
}

sub newitems_exist {
	for (@feeds) {
		return 1 if $_->get_newitems;
	}
	return 1;
}

sub clear_newitems {
	for (@feeds) {
		$_->clear_newitems;
		$_->reset_newitems;
	}
}

sub clear_newitems_in_feed {
	my (undef,$feed) = @_;
	$feed->clear_newitems;
	$feed->reset_newitems;
}

sub _ {
	my $str = shift;
	my %params = @_;
	my $translated = gettext($str);
	if (scalar(keys(%params)) > 0) {
		foreach my $key (keys %params) {
			$translated =~ s/\{$key\}/$params{$key}/g;
		}
	}
	return $translated;
}

1;
