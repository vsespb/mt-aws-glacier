#!/usr/bin/env perl

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
use Test::More tests => 4;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use Test::MockModule;
use TestUtils;

warning_fatal();


my $rootdir = 'root_dir';

#type=> 'CREATED', time => time(), archive_id => $archive_id, filesize => $data->{filesize}, final_hash => $data->{final_hash}, relfilename => $data->{relfilename}
my $data = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	size => 7684356,
	'time' => 1355666755,
	mtime => 1355566755,
	relfilename => 'def/abc',
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
	jobid => '6JpQ39WaMaD8O2N5BU5ieEPyAwtGLNdmNmYvomLjvD4JpivO3GwfCWs_sDnla6gl1Y9v-ceUdqU-pqaaz8FgOqc-yxZG'
};

#
# Test parsing line of Journal version 'B'
#

# CREATED /^A\t(\d+)\tCREATED\t(\S+)\t(\d+)\t(\d+)\t(\S+)\t(.*?)$/
{
	my $J = App::MtAws::Journal->new(output_version => 'B', journal_file=>'x', root_dir => $rootdir);

	my ($line);

	my $mock = Test::MockModule->new('App::MtAws::Journal');
	$mock->mock('_write_line', sub { (undef, $line) = @_; });
	$mock->mock('_time', sub { $data->{time} });

	$J->add_entry({ type=> 'CREATED', time => $data->{time}, mtime => $data->{mtime}, archive_id => $data->{archive_id}, size => $data->{size}, treehash => $data->{treehash}, relfilename => $data->{relfilename} });
	ok($line eq "B\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}");
}

# mtime=NONE
{
	my $J = App::MtAws::Journal->new(output_version => 'B', journal_file=>'x', root_dir => $rootdir);

	my ($line);

	my $mock = Test::MockModule->new('App::MtAws::Journal');
	$mock->mock('_write_line', sub { (undef, $line) = @_; });
	$mock->mock('_time', sub { $data->{time} });

	$J->add_entry({ type=> 'CREATED', time => $data->{time}, mtime => undef, archive_id => $data->{archive_id}, size => $data->{size}, treehash => $data->{treehash}, relfilename => $data->{relfilename} });
	ok($line eq "B\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\tNONE\t$data->{treehash}\t$data->{relfilename}");
}

# DELETED
{
	my $J = App::MtAws::Journal->new(output_version => 'B', journal_file=>'x', root_dir => $rootdir);

	my ($line);

	my $mock = Test::MockModule->new('App::MtAws::Journal');
	$mock->mock('_write_line', sub { (undef, $line) = @_; });
	$mock->mock('_time', sub { $data->{time} });

	$J->add_entry({ type=> 'DELETED', time => $data->{time}, archive_id => $data->{archive_id}, relfilename => $data->{relfilename} });
	ok($line eq "B\t$data->{time}\tDELETED\t$data->{archive_id}\t$data->{relfilename}");
}

# RETRIEVE_JOB
{
	my $J = App::MtAws::Journal->new(output_version => 'B', journal_file=>'x', root_dir => $rootdir);

	my ($line);

	my $mock = Test::MockModule->new('App::MtAws::Journal');
	$mock->mock('_write_line', sub { (undef, $line) = @_; });
	$mock->mock('_time', sub { $data->{time} });

	$J->add_entry({ type=> 'RETRIEVE_JOB', time => $data->{time}, archive_id => $data->{archive_id}, job_id => $data->{jobid}});
	ok($line eq "B\t$data->{time}\tRETRIEVE_JOB\t$data->{archive_id}\t$data->{jobid}");
}

1;
