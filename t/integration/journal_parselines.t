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
use Test::More tests => 12;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use App::MtAws::Exceptions;
use TestUtils;
use File::Path;

warning_fatal();

my $mtroot = get_temp_dir();
my $localroot = "$mtroot/cmd_check_local_hash";
my $journal = "$localroot/journal";
my $rootdir = "$localroot/root";
mkpath($localroot);
mkpath($rootdir);

my $data = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	job_id => "HdGDbije6lWPT8Q8S3uOWJF6777MWRlrfMGDr688888888888zwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	size => 7684356,
	'time' => 1355666755,
	mtime => 1355566755,
	relfilename => 'def/abc',
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
};


sub create_journal(@)
{
	
	open F, ">:encoding(UTF-8)", $journal;
	print F for (@_);
	close F;
}


sub assert_last_line_exception
{
	my ($line) = @_;
	my $err = $@;
	cmp_deeply $err, superhashof(exception 'journal_format_error' => "Invalid format of journal, line %lineno% not fully written", lineno => $line),
		"should throw exception if last line broken";
}

unlink $journal;
{
	create_journal "A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}\n";
	my $J = App::MtAws::Journal->new(output_version => 'A', journal_file=> $journal, root_dir => $rootdir);
	$J->read_journal(should_exist => 1);
	ok $J->{journal_h}->{$data->{relfilename}}, "should work";
}

{
	create_journal "A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}\r\n";
	my $J = App::MtAws::Journal->new(output_version => 'A', journal_file=> $journal, root_dir => $rootdir);
	$J->read_journal(should_exist => 1);
	ok $J->{journal_h}->{$data->{relfilename}}, "should work with CRLF";
}

{
	create_journal "A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}";
	my $J = App::MtAws::Journal->new(output_version => 'A', journal_file=> $journal, root_dir => $rootdir);
	ok ! defined eval { $J->read_journal(should_exist => 1); 1; }, "should not work without newline";
	assert_last_line_exception(1);
}

{
	create_journal "A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}\n",
		"A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}";
	my $J = App::MtAws::Journal->new(output_version => 'A', journal_file=> $journal, root_dir => $rootdir);
	ok ! defined eval { $J->read_journal(should_exist => 1); 1; }, "should not work without newline, when it's not first line";
	assert_last_line_exception(2);
}

{
	create_journal "A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}\n",
		"FFFFFFFFF";
	my $J = App::MtAws::Journal->new(output_version => 'A', journal_file=> $journal, root_dir => $rootdir);
	ok ! defined eval { $J->read_journal(should_exist => 1); 1; }, "should not work without newline, when it's not first line, and when line is broken";
	assert_last_line_exception(2);
}

{
	create_journal "A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}\n",
		"X\tZZZZZZZZ";
	my $J = App::MtAws::Journal->new(output_version => 'A', journal_file=> $journal, root_dir => $rootdir);
	ok ! defined eval { $J->read_journal(should_exist => 1); 1; }, "should not work without newline, when it's not first line, and when line is from future";
	assert_last_line_exception(2);
}

{
	create_journal "A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}\n",
		" ";
	my $J = App::MtAws::Journal->new(output_version => 'A', journal_file=> $journal, root_dir => $rootdir);
	ok ! defined eval { $J->read_journal(should_exist => 1); 1; }, "should not work without newline, when it's not first line, and when this line is just a single space";
	assert_last_line_exception(2);
}

unlink $journal;
