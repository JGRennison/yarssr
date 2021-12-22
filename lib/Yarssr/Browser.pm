package Yarssr::Browser;

use Yarssr::Config;

use constant TRUE=>1;

sub launch_url {
	my $class = shift;
        my $url = shift;

        if (Yarssr::Config->get_usegnome) {
                Gnome2::URL->show($url);
        }
        else {
                if ($child = fork)
                {
                        Glib::Timeout->add(200,
                                sub {
                                        my $kid = waitpid($child,WNOHANG);
                                        $kid > 0 ? return 0 : return 1;
                                }
                        );
                }
                else {
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
}

1;
