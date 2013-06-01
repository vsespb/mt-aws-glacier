#!/usr/bin/perl

# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use utf8;
use Test::More tests => 28;
use Test::Deep;
use File::Path;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use App::MtAws::Exceptions;
use Test::MockModule;
use POSIX;
use Carp;
use TestUtils;
use File::Temp ();

warning_fatal();

my $TEMP = File::Temp->newdir();
my $mtroot = $TEMP->dirname();
my $rootdir = 'def';
my $file = "$mtroot/journal_open_mode";
my $fixture = "A\t123\tCREATED\tasfaf\t1123\t1223\tahdsgBd\tabc/def";


chmod 0744, $file if -e $file;


# checking when reading journal

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file, $fixture);
	eval {
		$J->read_journal();
	};
	ok $@ ne '', "should die if called without should_exist even if file exsit";
}

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	unlink($file);
	eval {
		$J->read_journal();
	};
	ok $@ ne '', "should die if called without should_exist if file missing";
}

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	unlink($file);
	eval {
		$J->read_journal(should_exist => 1);
	};
	ok $@ ne '', "should_exist should work when true and file missing";
}

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file, $fixture);
	chmod 0000, $file;
	ok ! defined eval {
		$J->read_journal(should_exist => 1);
		1;
	};
	chmod 0744, $file;
	unlink($file);
	ok is_exception('journal_open_error'), "should_exist should work when true and file missing";
	is get_exception->{message}, "Unable to open journal file %string filename% for reading, errno=%errno%";
	is get_exception->{errno}+0, EACCES;
	ok length(get_exception->{errno}) > 4; # should be a string, not a number
	is get_exception->{filename}, $file;
}

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file);
	eval {
		$J->read_journal(should_exist => 1);
	};
	ok $@ eq '', "should_exist should work when true and file exists";
}

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file, $fixture);
	eval {
		$J->read_journal(should_exist => 1);
	};
	ok $@ eq '', "should_exist should work when true and file exists and there is data";
}

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file);
	eval {
		$J->read_journal(should_exist => 0);
	};
	ok $@ eq '', "should_exist should work when false and file empty";
}

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	create($file, $fixture);
	eval {
		$J->read_journal(should_exist => 0);
	};
	ok $@ eq '', "should_exist should work when false and file contains data";
}

{
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	
	unlink($file);
	eval {
		$J->read_journal(should_exist => 0);
	};
	ok $@ eq '', "should_exist should work when false and no file";
}

{
	for my $mode (qw/0 1/) {
		my $J = App::MtAws::Journal->new(journal_file=>$mtroot, root_dir => $rootdir);
		
		eval {
			$J->read_journal(should_exist => $mode);
		};
		ok $@ ne '', "should die if called for directory";
	}
}

# checking when writing journal
{
	unlink($file);
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	$J->open_for_write();

	$J->_write_line($fixture);
	ok -s $file, "should write to file, even without closing file";
}

{
	unlink($file);
	create($file, $fixture);
	chmod 0444, $file;
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	ok ! defined eval {
		$J->open_for_write();
		1;
	};
	chmod 0744, $file;
	unlink($file);
	
	ok is_exception('journal_open_error'), "should_exist should work when true and file missing";
	is get_exception->{message}, "Unable to open journal file %string filename% for writing, errno=%errno%";
	is get_exception->{errno}+0, EACCES;
	ok length(get_exception->{errno}) > 4; # should be a string, not a number
	is get_exception->{filename}, $file;
}

{
	unlink($file);
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
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
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	$J->open_for_write();
	$J->_write_line($fixture);
	ok -s $file == 2* ( bytes::length($fixture) + length("\n") ), "should append";
}

{
	unlink($file);
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
	eval { $J->_write_line($fixture); };
	ok($@ ne '', "write to closed file should die");
}

{
	unlink($file);
	my $J = App::MtAws::Journal->new(journal_file=>$file, root_dir => $rootdir);
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

1;

