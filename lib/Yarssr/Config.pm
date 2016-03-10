package Yarssr::Config;

use Yarssr;
use Yarssr::Feed;
use Data::Dumper;

use warnings;
use strict;

our $configdir = $ENV{HOME}.'/.yarssr/';
our $icondir = $configdir.'icons/';
my $statedir = $configdir.'state/';
my $config = $configdir.'config';

my $options;
my $timer;

sub init {
	my $class = shift;
	$options = load_config();
	if ($options->{'startonline'}) {
		$timer = Glib::Timeout->add($options->{'interval'} * 60_000,
			sub{ Yarssr->download_all; 1; });
	}
}

sub load_config {
	Yarssr->log_debug(_("Loading previous session"));
	my $return = {
		browser => 'mozilla',
		interval => 60,
		usegnome => 0,
		maxfeeds => 8,
		online	 => 1,
		startonline => 1,
	};
	
	if (! -e $configdir)
	{
		mkdir $configdir 
			or warn "Failed to make config directory: $!\n";
	}
	if (! -e $icondir)
	{
		mkdir $icondir
			or warn "Failed to make icons directory: $!\n";
	}
	if (! -e $statedir) {
	    mkdir $statedir
	    	or warn "Failed to make state directory: $!\n";
	}
	if (-e $config) {
		open (CONFIG,"<",$config)
			or warn "Failed to open config file for reading: $!\n";
		while(<CONFIG>)
		{
			
			chomp;
			
			if (/^feed=(.*);(.*);(\d)(?:;(.*):(.*))?/) 
			{
				my $feed = Yarssr::Feed->new(
					url	=> $1,
					title	=> $2,
					enabled	=> $3,
					username => $4,
					password => $5,
				);

				Yarssr->add_feed($feed);
				#load_state($feed);
			}
			elsif (/^interval=(\d+)/)
			{
				$return->{interval} = $1;
			}
			elsif (/^maxfeeds=(\d+)/)
			{
				$return->{maxfeeds} = $1;
			}
			elsif (/^browser=(.*)/)
			{
				$return->{browser} = $1;
			}		
			elsif (/^usegnome=(\d)/)
			{
				$return->{usegnome} = $1;
			}
			elsif (/^startonline=(\d)/)
			{
				$return->{startonline} = $1;
				$return->{online} = $return->{startonline};
			}
		}
		close(CONFIG)
	}

	Yarssr->log_debug(_("Successfully loaded config"));
	return $return; 
}

sub write_config
{
     Yarssr->log_debug(_("Writing config"));
	open (CONFIG,">",$config)
		or warn "Failed to open config file for writing: $!\n";
	print CONFIG "interval=".$options->{'interval'}."\n";
	print CONFIG "maxfeeds=".$options->{'maxfeeds'}."\n";
	print CONFIG "browser=".$options->{'browser'}."\n";
	print CONFIG "usegnome=".$options->{'usegnome'}."\n";
	print CONFIG "startonline=".$options->{'startonline'}."\n";
	for my $feed (Yarssr->get_feeds_array)
	{
		print CONFIG "feed=".$feed->get_url.";".$feed->get_title.
		";".$feed->get_enabled.";".$feed->get_username.":".
		$feed->get_password."\n";
	}
	close(CONFIG);
}

sub write_states {
	for (Yarssr->get_feeds_array) {
		write_state(undef,$_);
	}
}

sub write_state
{
	my (undef,$feed) = @_;

	
    if (! -e $statedir)
	{
		mkdir $statedir
		or warn "Failed to make statefile directory: $!\n";
	}
	
	Yarssr->log_debug(_("Writing state for {feed}",feed => $feed->get_title));
	
	my $rss = new XML::RSS (version => '1.0');
	$rss->channel(
		title	=> $feed->get_title,
		link	=> $feed->get_url,
	);
	my $count = 0;
	for my $item ($feed->get_items_array) {
	    # Limit number of items per feed to save
	    last if $count++ >= 100;
		my $status = 1;
		$status = 2 if ( $item->get_status > 1);

		$rss->add_item(
			title	=> $item->get_title,
			link	=> $item->get_url,
			dc	=> {
				description	=> "read: ".$status,
			},
		);
	}
	open RSS,">:utf8",$statedir.$feed->get_title.".xml";
	print RSS $rss->as_string or die $!;
	close RSS;
	
	return 0;
}

sub load_initial_state {
	for (Yarssr->get_feeds_array) {
		load_state($_);
	}
	Yarssr->log_debug(_("Successfully loaded previous session"));
}

sub load_state
{
	my $feed = shift;
	my $file = $statedir.$feed->get_title.".xml";
	if (-e $file) {
		Yarssr->log_debug(_("Loading state for {feed}",feed => $feed->get_title));
		my $rss = new XML::RSS;
		eval { $rss->parsefile($file) };
		return if $@;
		for (@{$rss->{'items'}}) {
			$_->{dc}{description} =~ /read: (\d)$/;
			my $read = $1;
			my $item = Yarssr::Item->new(
				title	=> $_->{'title'},
				url	=> $_->{'link'},
				parent	=> $feed,
			);
			$item->set_status($read);
			$feed->add_item($item);
		}
	}
}

sub set_maxfeeds
{
	my $class = shift;
	my $maxfeeds = shift;
	if ($maxfeeds != $options->{'maxfeeds'})
	{
		$options->{'maxfeeds'} = $maxfeeds;
	}
}

sub set_interval
{
	my $class = shift;
	my $interval = shift;
	Yarssr->log_debug(_("Updating interval timer"));
	$options->{'interval'} = $interval;
	if ($options->{online}) {
		Glib::Source->remove($timer) if $timer;
		$timer = Glib::Timeout->add($interval * 60_000,
		    sub{ Yarssr->download_all; Yarssr::GUI->redraw_menu; 1; });
	}
}

sub set_browser
{
	my $class = shift;
	$options->{'browser'} = shift;
}

sub set_usegnome
{
	my $class = shift;
	$options->{'usegnome'} = shift;
}

sub process
{
    my $class = shift;
    my ($new_interval,$new_maxfeeds,$new_browser,
		$new_usegnome,$newfeedlist,$online) = @_;
    my $rebuild = 0;

    $options->{'browser'} = $new_browser;
    $options->{'usegnome'} = $new_usegnome;
	
	if ($online) {
		$options->{'startonline'} = 1;
	}
	else {
		$options->{'startonline'} = 0;
	}
	
	if ($new_interval != $options->{'interval'}) {
    	set_interval(undef,$new_interval);
	}

    for my $url (keys %{$newfeedlist}) {
	
		my $feed;
	
		# If this feed doesn't exists add it
		unless ($feed = Yarssr->get_feed_by_url($url)) {
			$feed = Yarssr::Feed->new(
			    url		=> $url,
			    title	=> $newfeedlist->{$url}[0],
			    enabled	=> 0,
				username => $newfeedlist->{$url}[2],
				password => $newfeedlist->{$url}[3],
			);
			Yarssr->add_feed($feed);
		}
	
		unless ($feed->get_enabled == $newfeedlist->{$url}[1]) {
			$feed->toggle_enabled if $feed->get_enabled != 3;
			$feed->update if $feed->get_enabled and $options->{'online'};
			$rebuild = 1;
		}
    }

    for my $feed (Yarssr->get_feeds_array) {
		unless (exists $newfeedlist->{$feed->get_url}) {
		    Yarssr->remove_feed($feed);
		    $rebuild = 1;
		}
	}

    $rebuild = 1 if ($options->{'maxfeeds'} != $new_maxfeeds);
    $options->{'maxfeeds'} = $new_maxfeeds;

    return $rebuild;
}

sub quit {
    write_config();
    write_states();
}

no strict;

foreach my $field (qw(browser usegnome interval maxfeeds online startonline)) {
	*{"get_$field"} = sub {
		return $options->{$field};
	};
}

sub set_online {
	my $class = shift;
	my $bool = shift;
	
	$options->{online} = $bool;

	if ($bool) {
		Yarssr->log_debug(_("Online mode"));
		Yarssr->download_all;
		set_interval(undef,$options->{interval});
	}
	else {
		Yarssr->log_debug(_("Offline mode"));
		if ($timer) {
			Glib::Source->remove($timer);
			$timer = undef;
		}
	}
}

1;
