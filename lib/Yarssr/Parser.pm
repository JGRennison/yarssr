package Yarssr::Parser;
use Data::Dumper;
use Yarssr::Item;
use Yarssr::Feed;
use XML::Parser;
use XML::RSS;

$XML::RSS::AUTO_ADD = 1;

sub parse {
	push @XML::Parser::Expat::Encoding_Path, $Yarssr::PREFIX."/share/yarssr/encfiles";
	my (undef,$feed,$content) = @_;
	Yarssr->log_debug("Parsing ".$feed->get_title);
	my $parser = new XML::Parser(Style => Tree);
	my $parsetree = eval{ $parser->parse($content) };

	if ($@) {
		Yarssr->log_debug($@);
		return;
	}

	if ($parsetree->[0] eq "rss" or $parsetree->[0] eq "rdf"
		or $parsetree->[0] eq "rdf:RDF") {
		return parse_rss($feed,$content);
	}
	elsif ($parsetree->[0] eq "feed") {
		return parse_atom($feed,$parsetree);
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

		for my $count (0 .. $#{$parser->{'items'}})
		{
			my $item = ${$parser->{'items'}}[$count];
			my $link = $item->{'link'};
			$link = $item->{'guid'} unless $link;

			# Fix amperstands
			$link =~ s/&amp;/&/g;

			my $article = Yarssr::Item->new(
				url	=> $link,
				title	=> $item->{'title'},
				id	=> $link."___".$item->{'title'},
			);
			push @items, $article;
		}
	}
	return @items;
}

sub parse_atom {
	my ($feed,$tree) = @_;
	my @items;
	for (my $i = 0;$i < $#{$tree->[1]};$i++) {
		if ($tree->[1][$i] eq "entry") {
			my $item = $tree->[1][++$i];
			my ($title,$link);
			for (my $j=0;$j < $#{$item};$j++) {
				if ($item->[$j] eq "title") {
					$title = $item->[++$j][$#{$item->[$j]}];
					$title =~ s/^\s*(.*)\s*$/$1/;
				}
				elsif ($item->[$j] eq "link"
					and $item->[++$j][0]{'rel'} eq "alternate") {
					$link = $item->[$j][0]{'href'};
				}
			}
			if ($title and $link) {
				my $article = Yarssr::Item->new(
					title	=> $title,
					url		=> $link,
					id		=> $link."___".$title,
				);
				push @items,$article;
			}
		}
	}
	return @items;
}

sub parse_opml {
	my ($class,$content) = @_;
	my @feeds;

	my $parser = new XML::Parser(Style => Tree);
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
