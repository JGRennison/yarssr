package Yarssr::Browser;

use Yarssr::Config;

use POSIX ":sys_wait_h";

use strict;
use warnings;

sub launch_url {
	my $class = shift;
	my $url = shift;

	if (my $child = fork) {
		Glib::Timeout->add(200,
			sub {
				my $kid = waitpid($child, WNOHANG);
				$kid > 0 ? return 0 : return 1;
			}
		);
	} else {
		my $b = Yarssr::Config->get_browser;
		my @b = split(' ', Yarssr::Config->get_browser);
		if (grep(/\%s/, @b))
		{
			map {grep(s/\%s/$url/, $_) => $_} @b;
		}
		else {
			push(@b, $url);
		}
		exec(@b) or warn "unable to launch browser\n";
		exit;
	}
}

1;
