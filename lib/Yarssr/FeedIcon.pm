package Yarssr::FeedIcon;

use strict;
use warnings;

use Yarssr::Fetcher;
use File::Slurp;
use AnyEvent;
use URI::URL;

sub new {
	my $class = shift;
	my $feed = shift;

	my $icondir = $Yarssr::Config::icondir;

	my $self = {
		iconfile    => $icondir.$feed->get_title . ".ico",
		feed        => $feed,
	};

	bless $self, $class;

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

sub update_if_stale {
	my $self = shift;
	my $interval;
	if (! -e $self->{'iconfile'}) {
		$self->update();
		return;
	} elsif (! -s $self->{'iconfile'}) {
		$interval = 12 * 60 * 60; # 12 hours
	} else {
		$interval = 4 * 24 * 60 * 60; # 4 days
	}
	if (time - $self->{feed}->get_icon_fetch_time() > $interval) {
		$self->update();
	}
}

sub update {
	my $self = shift;

	my $icon_url = $self->{feed}->get_icon_url();
	my $cv;
	if ($icon_url) {
		$cv = $self->_try_update($icon_url, -s $self->{'iconfile'} && $self->{feed}->get_icon_last_modified());
	} else {
		my $feed_url = $self->{feed}->get_url();
		$cv = AnyEvent::condvar;
		$self->_try_update_list($cv, URI::URL->new('/favicon.ico', $feed_url)->abs, URI::URL->new('/favicon.png', $feed_url)->abs);
	}
	$cv->cb(sub {
		$self->_fail_update() unless $cv->recv;
	});
}

sub _try_update_list {
	my ($self, $ret_cv, @urls) = @_;
	$self->_try_update(shift @urls)->cb(sub {
		my ($cv) = @_;
		if ($cv->recv) {
			$ret_cv->send(1);
		} elsif (scalar @urls) {
			$self->_try_update_list($ret_cv, @urls);
		} else {
			$ret_cv->send(0);
		}
	});
}

sub _try_update {
	my ($self, $icon_url, $last_modified) = @_;
	my $ret_cv = AnyEvent::condvar;
	my $cv = Yarssr::Fetcher->fetch_icon($icon_url);
	$cv->cb(sub {
		my $info = $cv->recv;
		if ($info->{type} ne 'text/html' and $info->{content}) {
			write_file($self->{'iconfile'}, { err_mode => 'carp', atomic => 1, binmode => ':raw' }, $info->{content});
			$self->{feed}->set_icon_url($icon_url);
			$self->{feed}->set_icon_fetch_time(time);
			$self->{feed}->set_icon_last_modified($info->{last_modified});
			$self->load_icon;
			$ret_cv->send(1);
		} elsif ($info->{type} ne 'text/html' and $info->{not_modified} and -s $self->{'iconfile'}) {
			$self->{feed}->set_icon_fetch_time(time);
			$ret_cv->send(1);
		} else {
			$ret_cv->send(0);
		}
	});
	return $ret_cv;
}

sub _fail_update {
	my $self = shift;
	if (! -e $self->{'iconfile'}) {
		write_file($self->{'iconfile'}, { err_mode => 'carp', atomic => 1, binmode => ':raw' }, "");
		$self->{feed}->set_icon_last_modified(undef);
	}
	$self->{feed}->set_icon_fetch_time(time);
	$self->load_icon;
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
		$pixbuf = $pixbuf->scale_simple(16, 16, 'bilinear')
			if ($pixbuf->get_height != 16);
	};

	$self->{'pixbuf'} = $pixbuf;
	return 1;
}

1;
