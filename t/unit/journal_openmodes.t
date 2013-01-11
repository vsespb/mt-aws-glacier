#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 10;
use Test::Deep;
use File::Path qw/mkpath/;
use lib qw{.. ../..};
use Journal;
use Test::MockModule;
use Carp;

my $mtroot = '/tmp/mt-aws-glacier-tests';
mkpath $mtroot;
my $rootdir = 'def';
my $file = "$mtroot/journal_open_mode";
my $fixture = "A\t123\tCREATED\tasfaf\t1123\t1223\tahdsgBd\tabc/def";


{
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file, $fixture);
	eval {
		$J->read_journal();
	};
	ok $@ ne '', "should die if called without should_exist even if file exsit";
}

{
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	remove($file);
	eval {
		$J->read_journal();
	};
	ok $@ ne '', "should die if called without should_exist if file missing";
}

{
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	remove($file);
	eval {
		$J->read_journal(should_exist => 1);
	};
	ok $@ ne '', "should_exist should work when true and file missing";
}

{
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file);
	eval {
		$J->read_journal(should_exist => 1);
	};
	ok $@ eq '', "should_exist should work when true and file exists";
}

{
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file, $fixture);
	eval {
		$J->read_journal(should_exist => 1);
	};
	ok $@ eq '', "should_exist should work when true and file exists and there is data";
}

{
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file);
	eval {
		$J->read_journal(should_exist => 0);
	};
	ok $@ eq '', "should_exist should work when false and file empty";
}

{
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file, $fixture);
	eval {
		$J->read_journal(should_exist => 0);
	};
	ok $@ eq '', "should_exist should work when false and file contains data";
}

{
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	remove($file);
	eval {
		$J->read_journal(should_exist => 0);
	};
	ok $@ eq '', "should_exist should work when false and no file";
}

{
	for my $mode (qw/0 1/) {
		my $J = Journal->new(journal_file=>$mtroot, root_dir => $rootdir);
		
		eval {
			$J->read_journal(should_exist => $mode);
		};
		ok $@ ne '', "should die if called for directory";
	}
}

sub create
{
	my ($file, $content) = @_;
	open F, ">:encoding(UTF-8)", $file;
	print F $content if defined $content;
	close F;
	
}

sub remove
{
	my ($file) = @_;
	unlink $file || confess if -e $file;
}

1;

