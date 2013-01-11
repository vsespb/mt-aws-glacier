#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 15;
use Test::Deep;
use File::Path;
use lib qw{.. ../..};
use Journal;
use Test::MockModule;
use Carp;

my $mtroot = '/tmp/mt-aws-glacier-tests';
mkpath $mtroot;
my $rootdir = 'def';
my $file = "$mtroot/journal_open_mode";
my $fixture = "A\t123\tCREATED\tasfaf\t1123\t1223\tahdsgBd\tabc/def";


# checking when reading journal

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

# checking when writing journal
{
	remove($file);
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	$J->open_for_write();
	$J->_write_line($fixture);
	ok -s $file, "should write to file, even without closing file";
}

{
	remove($file);
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	$J->open_for_write();
	$J->_write_line($fixture);
	$J->close_for_write;
	ok( -s $file, "close for write should work");
}

{
	use bytes;
	no bytes;
	create($file, $fixture);
	ok -s $file == bytes::length($fixture) + length("\n"), "assume length";
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	$J->open_for_write();
	$J->_write_line($fixture);
	ok -s $file == 2* ( bytes::length($fixture) + length("\n") ), "should append";
}

{
	remove($file);
	my $J = Journal->new(journal_file=>$file, root_dir => $rootdir);
	eval { $J->close_for_write; };
	ok($@ ne '', "close for write should die if file was not opened");
}

sub create
{
	my ($file, $content) = @_;
	open F, ">:encoding(UTF-8)", $file;
	print F $content."\n" if defined $content;
	close F;
	
}

sub remove
{
	my ($file) = @_;
	unlink $file || confess if -e $file;
}

1;

