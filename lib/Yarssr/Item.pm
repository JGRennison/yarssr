package Yarssr::Item;

use strict;
use warnings;

sub new {
	my $class = shift;
	my (%options) = @_;

	my $self = { %options };

	# Item status used to determine which icon
	# to use when creating the menu
	# 4 = not added to the menu yet
	# 3 = new
	# 2 = unread
	# 1 = read

	$self->{'status'} = 4;

	bless $self, $class;
}

sub get_pseudo_id {
	my $self = shift;
	return $self->{url} . "___" . $self->{title};
}

foreach my $field (qw(title url status parent id)) {
	no strict 'refs';

	*{"get_$field"} = sub {
		my $self = shift;
		return $self->{$field};
	};
	*{"set_$field"} = sub {
		my $self = shift;
		$self->{$field} = shift;
		return 1;
	};
}

1;
