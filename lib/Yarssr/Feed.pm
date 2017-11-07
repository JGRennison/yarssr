package Yarssr::Feed;

use strict;
use warnings;

use Yarssr::Fetcher;
use Yarssr::FeedIcon;
use AnyEvent;

use constant TRUE => 1;

sub new {
	my $class  = shift;
	my %settings = @_;

	my $self = {%settings};
	$self->{'items'} = [];
	$self->{'newitems'} = 0;
	$self->{'siteurl'} = '';

	$self->{'menu'} = undef;

	# attribute to keep track of status of the
	# feed.
	#
	# 0 = no error
	# 1 = downloading error
	# 2 = parsing error

	$self->{'error'} = 0;

	bless $self, $class;

	$self->{'icon'} = Yarssr::FeedIcon->new($self);

	$self->{'downloading'} = 0;

	return $self;
}

sub get_items_array {
	my $self = shift;
	return @{$self->{'items'}};
}

sub add_item {
	my $self = shift;
	my $item = shift;

	ref $item eq 'Yarssr::Item' or die;

	push @{$self->{'items'}}, $item;
	#reverse(sort {$a->get_date <=> $b->get_date} @{$self->{'items'}});
}

sub unshift_item {
	my $self = shift;
	my $item = shift;

	ref $item eq 'Yarssr::Item' or die;

	unshift @{$self->{'items'}}, $item;
	#reverse(sort {$a->get_date <=> $b->get_date} @{$self->{'items'}});
}

foreach my $field (qw(title date url interval menu username password last_modified icon_last_modified excludenew)) {
	no strict 'refs';

	*{"get_$field"} = sub {
		my $self = shift;
		defined $self->{$field} ? return $self->{$field} : return "";
	};
	*{"set_$field"} = sub {
		my $self = shift;
		$self->{$field} = shift;
		return 1;
	};
}
foreach my $field (qw(icon_fetch_time)) {
	no strict 'refs';

	*{"get_$field"} = sub {
		my $self = shift;
		defined $self->{$field} ? return $self->{$field} : return 0;
	};
	*{"set_$field"} = sub {
		my $self = shift;
		$self->{$field} = shift;
		return 1;
	};
}

sub get_icon {
	my $self = shift;
	return $self->{'icon'}->get_pixbuf;
}

sub get_state_file_stem {
	my $self = shift;
	return $self->get_title =~ s/\//_/rg;
}

sub enable {
	my $self = shift;
	$self->{'enabled'} = 1;
	return 1;
}

sub disable {
	my $self = shift;
	$self->{'enabled'} = 0;
	return 1;
}

sub enable_and_flag {
	my $self = shift;
	$self->{'enabled'} = 3;
	return 1;
}

sub toggle_enabled {
	my $self = shift;
	if ($self->{'enabled'}) {
		$self->disable;
	}
	else {
		$self->enable;
	}
}

sub new_menu {
	my $self = shift;
	$self->{'menu'} = undef;
	$self->{'menu'} = Gtk2::Menu->new;
}

sub check_url {
	my $self = shift;
	my $url = shift;
	for (@{$self->{'items'}}) {
		return 1 if $_->get_url eq $url;
	}
	return 0;
}

sub get_enabled {
	my $self = shift;
	return $self->{'enabled'};
}

sub update {
	my $self = shift;
	my @items;
	my $cv = AnyEvent::condvar;

	if ($self->{downloading}) {
		$cv->send(0);
		return $cv;
	}

	$self->{'icon'}->update_if_stale();

	# Set new items as unread
	#for ($self->get_items_array) {
	#	$_->set_status(2) if $_->get_status > 2;
	#}

	#$self->reset_newitems();
	$self->enable if ($self->get_enabled == 3);
	my $content_cv = Yarssr::Fetcher->fetch_feed($self);
	$content_cv->cb(sub {
		my $info = $content_cv->recv;
		my $content = $info->{content};
		# If download is successful
		if ($content) {
			$self->{status} = 0;

			unless (@items = Yarssr::Parser->parse($self,$content)) {
				$self->{status} = 2;
			}

			for my $item (reverse @items) {
				my $existing_item = $self->get_item_by_id($item->get_id(), $item->get_pseudo_id());
				if ($existing_item) {
					$existing_item->set_id($item->get_id());
					$existing_item->set_url($item->get_url());
					$existing_item->set_title($item->get_title());
				} else {
					$self->unshift_item($item);
					$item->set_parent($self);
				}
			}
			$self->set_last_modified($info->{last_modified});
			$self->{downloading} = 0;
			$cv->send(1);
		} else {
			# If download fails
			my $ok = $info->{not_modified};
			$self->{status} = $ok ? 0 : 1;
			$self->{downloading} = 0;
			$cv->send($ok ? 1 : 0);
		}
	});
	return $cv;
}

sub get_status {
	my $self = shift;
	return $self->{status};
}

sub get_item_by_id {
	my $self = shift;
	my $id = shift;
	my $pseudo_id = shift;
	for (@{$self->{'items'}}) {
		return $_ if ($id && $_->get_id() && ($_->get_id() eq $id)) || ($pseudo_id && $_->get_pseudo_id() && ($_->get_pseudo_id() eq $pseudo_id));
	}
	return 0;
}

sub add_newitem {
	my $self = shift;
	return ++$self->{'newitems'};
}

sub subtract_newitem {
	my $self = shift;
	return --$self->{'newitems'};
}

sub get_newitems {
	my $self = shift;
	return $self->{'newitems'};
}

sub reset_newitems {
	my $self = shift;
	$self->{'newitems'} = 0;
}

sub clear_newitems {
	my $self = shift;
	for ($self->get_items_array) {
		$_->set_status(2) if $_->get_status > 2;
	}
}

sub get_icon_url {
	my $self = shift;
	return $self->{'icon_url'};
}

sub set_icon_url {
	my $self = shift;
	my $url = shift;
	$self->{'icon_url'} = $url;
}

sub set_icon_url_update {
	my $self = shift;
	my $url = shift;
	if (!$self->{'icon_url'} || $self->{'icon_url'} ne $url) {
		$self->{'icon_url'} = $url;
		$self->{'icon'}->update();
	}
}

1;
