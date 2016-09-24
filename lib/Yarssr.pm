package Yarssr;

use strict;
use warnings;

use Gnome2;
use Gtk2;
use Yarssr::GUI;
use Yarssr::Config;
use Locale::gettext;
use POSIX qw/setlocale/;
use AnyEvent;
use base 'Exporter';

use vars qw(
	$LIBDIR		$PREFIX		$NAME	$VERSION
	$AUTHOR		@CO_AUTHORS	$URL	$LICENSE);

our $NAME		= 'yarssr';
our $VERSION	= '0.3.0~prerelease';
our $LICENSE	= 'GNU General Public License (GPL)';
our $URL		= 'https://github.com/JGRennison/yarssr';
our $OLDURL		= 'http://yarssr.sf.net';
our $AUTHOR		= "Lee Aylward";
our @COAUTHORS	= ( "James Curbo","Dan Leski","Jonathan Rennison" );
our @TESTERS	= ( "Thanks to Joachim Breitner for testing\n" .
					"and maintaining the Debian package");
our $debug = 0;
our @EXPORT_OK = qw(_);

my @feeds;
my $last_download_all_time = 0;
$0 = $NAME;

sub init {
	Yarssr->log_debug("init");
	# il8n stuff
	my $locale = (defined($ENV{LC_MESSAGES}) ? $ENV{LC_MESSAGES} : $ENV{LANG});
	setlocale(LC_ALL, $locale);
	bindtextdomain(lc($NAME), sprintf('%s/share/locale', $PREFIX));
	textdomain(lc($NAME));

	Gnome2::Program->init($0, $VERSION);
	Yarssr::Config->init;
	Yarssr::Config->load_initial_state;

	my $cv = AnyEvent::condvar;
	$cv->cb(\&initial_launch);
	Yarssr::GUI->init($cv);
}

sub quit {
	Yarssr::Config->quit;
	Yarssr::GUI->quit;
}

sub log_debug {
	return unless $debug;
	my ($sec, $min, $hour, undef) = localtime;
	my $time = sprintf("%02d:%02d:%02d", $hour, $min, $sec);
	print STDERR "[$time] $_[1]\n" if -t;
}


sub initial_launch {
	Yarssr->log_debug("initial_launch");
	Yarssr::GUI->redraw_menu;
	Yarssr::Config->schedule_timer;

	return 0;
}

sub add_feed {
	my (undef, $feed)  = @_;
	ref $feed eq 'Yarssr::Feed' or die;

	return 0 if (Yarssr->get_feed_by_url($feed->get_url) and
		Yarssr->get_feed_by_title($feed->get_title));

	push @feeds, $feed;
	@feeds = sort { lc $a->get_title cmp lc $b->get_title } @feeds;
	return 1;
}

sub get_feeds_array {
	return @feeds;
}

sub download_feed {
	my (undef, $feed) = @_;
	my $activity_guard = Yarssr::GUI->get_icon_activity_guard();
	$feed->update->cb(sub {
		undef $activity_guard;
		Yarssr::GUI->redraw_menu;
		Yarssr::Config->write_states;
	});
}

sub download_all {
	Yarssr->log_debug("download_all");
	$last_download_all_time = time;
	my $cv = AnyEvent->condvar;
	my $activity_guard = Yarssr::GUI->get_icon_activity_guard();
	$cv->begin;
	for my $feed (@feeds) {
		if ($feed->get_enabled) {
			$cv->begin;
			$feed->update->cb(sub { $cv->end; });
		}
	}
	$cv->end;
	$cv->cb(sub {
		undef $activity_guard;
		Yarssr::GUI->redraw_menu;
		Yarssr::Config->write_states;
		Yarssr::Config->schedule_timer;
	});
	return 1;
}

sub get_last_download_all_time {
	return $last_download_all_time;
}

sub get_feed_by_url {
	my (undef, $url) = @_;
	for (@feeds) {
		return $_ if $_->get_url eq $url;
	}
	return 0;
}

sub get_feed_by_title {
	my (undef, $title) = @_;
	for (@feeds) {
		return $_ if $_->get_title eq $title;
	}
	return 0;
}

sub remove_feed {
	my (undef, $feed) = @_;
	die unless ref $feed eq 'Yarssr::Feed';
	for (0 .. $#feeds) {
		if ($feeds[$_]->get_title eq $feed->get_title) {
			splice @feeds, $_, 1;
			$feed = undef;
			last;
		}
	}
}

sub get_total_newitems {
	my $newitems = 0;
	for (@feeds) {
		$newitems += $_->get_newitems unless $_->get_excludenew;
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
	my (undef, $feed) = @_;
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
