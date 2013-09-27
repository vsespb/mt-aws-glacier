#!/usr/bin/env perl

use strict;
use warnings;
use v5.10;
use utf8;
use lib '../../lib';
use Data::Dumper;
use Carp;
use File::Basename;
use Encode;
use File::Path qw/mkpath rmtree/;
use Getopt::Long;
use App::MtAws::TreeHash;


our %task_seen;
our @priority = qw/command subcommand/;
our $data;
our %priority;
{
	my $i;
	map { $priority{$_} = ++$i } @priority;
}
our %filter;

our $FILTER='';
GetOptions ("filter=s" => \$FILTER );

map {
	if (my ($k, $vals) = /^([^=]+)=(.*)$/) {
		my @vals = split ',', $vals;
		$filter{$k} = { map { $_ => 1 } @vals };
	} else {
		confess $FILTER, $_;
	}
} split (' ', $FILTER);

binmode STDOUT, ":encoding(UTF-8)";

sub bool($)
{
	$_[0] ? 1 : 0
}

sub lfor(@&)
{
	my ($cb, $key, @values) = (pop, @_);
	for (@values) {
		if (my ($mainkey) = $key =~ /\A\-(.*)$/) {
			confess if defined $data->{$mainkey};
		} else {
			confess if defined $data->{"-$key"};
		}
		local $data->{$key} = $_;
		$cb->();
	}
}

sub get($) {
	my $key = shift;
	confess unless $key;
	confess if $key =~ /\A\-/;
	confess if defined $data->{$key} && defined $data->{"-$key"};
	my $v;
	if (defined ($v = $data->{$key})) {
		$v;
	} elsif (defined ($v = $data->{"-$key"})) {
		$v;
	} else {
		confess [$key, Dumper $data];
	}
};

sub AUTOLOAD
{
	use vars qw/$AUTOLOAD/;
	$AUTOLOAD =~ s/^.*:://;
	get("$AUTOLOAD");
};



sub process
{
	for (sort keys %$data) {
		no warnings 'uninitialized';
		return if ($filter{$_} && !$filter{$_}{$data->{$_}} && !$filter{$_}{$data->{"-$_"}});
	}

	my $task = ( join(" ",
		map {
			my $v = $data->{$_};
			$_ =~ s/^\-//; "$_=$v"
		} sort {
			( ($priority{$a}||100_000) <=> ($priority{$b}||100_000) ) || ($a cmp $b);
		} grep {
			!/\A\-/
		} keys %$data
	));

	return  if $task_seen{$task};
	$task_seen{$task}=1;
	print $task, "\n";
}

sub gen_filename
{
	my ($cb, @types) = (pop, @_);
	lfor -filename_type => @types, sub {
		lfor filename => do {
			if (filename_type() eq 'zero') {
				"0"
			} elsif (filename_type() eq 'default') {
				"somefile"
			} elsif (filename_type() eq 'russian') {
				"файл"
			} else {
				confess;
			}
		}, $cb;
	}
}

sub gen_filesize
{
	my ($cb, $type) = (pop, shift);
	lfor -filesize_type => $type, sub {
		lfor filesize => do {
			if (filesize_type() eq '1') {
				1
			} elsif (filesize_type() eq '4') {
				1, 1024*1024-1, 4*1024*1024+1
			} elsif (filesize_type() eq 'big') {
				1, 1024*1024-1, 4*1024*1024+1, 45*1024*1024-156897
			} else {
				confess
			}

		}, $cb;
	}
}

sub roll_partsize
{
	my $partsize = shift;
	if ($partsize eq '1') {
		1
	} elsif ($partsize eq '2') {
		1, 2
	} elsif ($partsize eq '4') {
		1, 2, 4
	} else {
		confess $partsize;
	}
}

sub roll_concurrency
{
	my $concurrency = shift;
	if ($concurrency eq '1') {
		1
	} elsif ($concurrency eq '2') {
		1, 2
	} elsif ($concurrency eq '4') {
		1, 2, 4
	} elsif ($concurrency eq '20') {
		1, 2, 4, 20
	} else {
		confess $concurrency;
	}
}

sub file_sizes
{
	my ($cb, $filesize, $partsize, $concurrency) = (pop, @_);
	gen_filesize $filesize, sub {
		lfor partsize =>roll_partsize($partsize), sub {
			lfor concurrency =>roll_concurrency($concurrency), sub {
				my $r = get("filesize") / (get("partsize")*1024*1024);
				if ($r < 3 && get "concurrency" > 2) {
					# nothing
				} else {
					$cb->();
				}
			}
		}
	}
}


sub roll_russian_encodings
{
	my ($encodings_type) = @_;
	if ($encodings_type eq 'none') {
		"UTF-8"
	} elsif ($encodings_type eq 'simple') {
		qw/UTF-8 KOI8-R/;
	} elsif ($encodings_type eq 'full') {
		qw/UTF-8 KOI8-R CP1251/;
	} else {
		confess $encodings_type;
	}
}

sub file_names
{
	my ($cb, $filenames_types, $filename_encodings_type, $terminal_encodings_type) = (pop, @_);
	gen_filename @$filenames_types,  sub {
		lfor -russian_text => bool(filename_type() eq 'russian'), sub {
			lfor -terminal_encoding_type => qw/utf singlebyte/, sub {
				if (get "russian_text" || get "terminal_encoding_type" eq 'utf') {
					lfor filenames_encoding => do {
						if (get "russian_text" && get "terminal_encoding_type" eq 'singlebyte') {
							roll_russian_encodings($filename_encodings_type);
						} else {
							"UTF-8"
						}
					}, sub {
					lfor terminal_encoding => do {
						if (get "russian_text" && get "terminal_encoding_type" eq 'singlebyte') {
							roll_russian_encodings($terminal_encodings_type);
						} else {
							"UTF-8"
						}
					}, $cb
					}
				}
			}
		}
	}
}

sub file_body
{
	my ($cb, @types) = (pop, @_);
	lfor filebody => @types, sub {
		if (filesize() == 1 || filebody() eq 'normal') {
			if (filename_type() eq 'default' || filebody() eq 'normal') {
				$cb->();
			}
		}
	}
}

lfor command => qw/sync/, sub {
	if (get "command" eq "sync") {
		lfor subcommand => qw/sync_new sync_modified/, sub {
			if (get "subcommand" eq "sync_new") {
				# testing filename stuff
				file_sizes 4, 2, 4, sub {
				file_names [qw/zero russian/], 'full', 'full', sub {
				file_body qw/normal/, sub {
					process();
				}}};
				# testing FSM stuff
				file_sizes 'big', 4, 20, sub {
				file_names [qw/default zero russian/], 'simple', 'none', sub {
				file_body qw/normal zero/, sub {
					process();
				}}};
			} elsif (get "subcommand" eq "sync_modified") {

				my @detect_cases = qw/
					treehash-matches
					treehash-nomatch
					mtime-matches
					mtime-nomatch
					mtime-and-treehash-matches-treehashfail
					mtime-and-treehash-matches-treehashok
					mtime-and-treehash-nomatch
					mtime-or-treehash-matches
					mtime-or-treehash-nomatch-treehashok
					mtime-or-treehash-nomatch-treehashfail
					always-positive
					size-only-matches
					size-only-nomatch
				/;

				lfor detect_case => @detect_cases, sub {
				# testing filename stuff
				file_sizes 1, 1, 1, sub {
				file_names [qw/zero russian/], 'simple', 'none', sub {
				file_body qw/normal/, sub {
					process();
				}}}};
			}
		}
	}
};





__END__
