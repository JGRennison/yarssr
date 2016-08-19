package Yarssr::Parser;

use strict;
use warnings;

use Data::Dumper;
use Yarssr::Item;
use Yarssr::Feed;
use XML::LibXML;
use XML::Parser;
use XML::RSS;

$XML::RSS::AUTO_ADD = 1;

sub parse {
	my (undef, $feed, $content) = @_;
	Yarssr->log_debug("Parsing " . $feed->get_title);
	my $parser = XML::LibXML->new();
	my $doc = eval{ $parser->parse_string($content) };

	if ($@) {
		Yarssr->log_debug($@);
		return;
	}

	my $root_node_type = $doc->documentElement()->localname;

	if ($root_node_type eq "rss" || $root_node_type eq "rdf"
		or $root_node_type eq "RDF") {
		return parse_rss($feed, $content);
	}
	elsif ($root_node_type eq "feed") {
		return parse_atom($feed, $doc);
	}
	else {
		Yarssr->log_debug("Cannot determine feed type");
		return ();
	}
}

sub parse_rss
{
	my ($feed,$content) = @_;
	my @items;
	my $parser = new XML::RSS;

	eval { $parser->parse($content); };

	if ($@) {
		Yarssr->log_debug($@);
		return;
	}
	else {

		eval {
			if ($parser->{'image'} && $parser->{'image'}->{'url'}) {
				$feed->set_icon_url_update($parser->{'image'}->{'url'});
			}
		};
		warn $@ if $@;

		for my $count (0 .. $#{$parser->{'items'}})
		{
			my $item = ${$parser->{'items'}}[$count];
			my $link = $item->{'link'};
			$link = $item->{'guid'} unless $link;
			my $id = $item->{'guid'};

			# Fix amperstands
			$link =~ s/&amp;/&/g;

			my $article = Yarssr::Item->new(
				url     => $link,
				title   => $item->{'title'},
				id      => $id,
			);
			push @items, $article;
		}
	}
	return @items;
}

sub parse_atom {
	my ($feed, $doc) = @_;
	my @items;

	my $xpc = XML::LibXML::XPathContext->new;
	$xpc->registerNs('x', $doc->documentElement()->namespaceURI());
	if ($doc->documentElement()->namespaceURI() ne 'http://www.w3.org/2005/Atom') {
		Yarssr->log_debug("Unexpected namespace: " . $doc->documentElement()->namespaceURI());
	}

	eval {
		my $icon;
		$icon = $_->textContent for $xpc->findnodes('x:logo', $doc->documentElement());
		$icon = $_->textContent for $xpc->findnodes('x:icon', $doc->documentElement());
		if ($icon) {
			$feed->set_icon_url_update($icon);
		}
	};
	warn $@ if $@;


	foreach my $entry ($xpc->findnodes('x:entry', $doc->documentElement())) {
		my ($title, $link, $id);
		foreach ($xpc->findnodes('x:title', $entry)) {
			$title = $_->textContent;
			$title =~ s/^\s*(.*)\s*$/$1/;
		}
		foreach ($xpc->findnodes('x:link', $entry)) {
			if (!length $_->getAttribute("rel") || $_->getAttribute("rel") eq "alternate") {
				$link = $_->getAttribute("href");
			}
		}
		foreach ($xpc->findnodes('x:id', $entry)) {
			$id = $_->textContent;
		}

		if ($title and $link) {
			my $article = Yarssr::Item->new(
				title	=> $title,
				url		=> $link,
				id		=> $id,
			);
			push @items, $article;
		}
	}
	return @items;
}

sub parse_opml {
	my ($class,$content) = @_;
	my @feeds;

	my $parser = new XML::Parser(Style => 'Tree');
	my $tree = eval{ $parser->parse($content) };

	if ($@) {
		Yarssr->log_debug($@);
		return;
	}

	for (my $i = 0;$i < $#{$tree->[1]};$i++) {
		if ($tree->[1][$i] eq "body") {
			my $body = $tree->[1][++$i];
			for (my $j = 0;$j < $#{$body};$j++) {
				if ($body->[$j] eq "outline") {
					my $item = $body->[++$j];
					my $feed = {
						title	=> $item->[0]{text},
						url		=> $item->[0]{xmlUrl},
					};
					push @feeds, $feed;
				}
			}
		}
	}
	return \@feeds;
}

1;
