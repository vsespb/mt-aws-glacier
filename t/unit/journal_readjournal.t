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
use Test::More tests => 31;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use Test::MockModule;
use TestUtils;

warning_fatal();

my $relfilename = 'def/abc';
my $rootdir = 'root_dir';
my $data = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	job_id => "HdGDbije6lWPT82222222226Ou9MWRlrfMGDr6T3rhXuDq33333333334l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	size => 7684356,
	'time' => 1355666755,
	mtime => 1355566755,
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
#	absfilename => File::Spec->rel2abs($relfilename, $rootdir)
};

#
# Test parsing line of Journal version 'A'
#

# CREATED
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($args);
		
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_add_filename', sub {	(undef, $args) = @_;});
		
		$J->process_line("A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$relfilename");
		$J->_index_archives_as_files();
		ok($args);
		ok( $args->{$_} eq $data->{$_}, $_) for qw/archive_id size time mtime treehash/;
		ok( $J->absfilename($args->{relfilename}) eq File::Spec->rel2abs($relfilename, $rootdir));
		is_deeply($J->{used_versions}, {'A'=>1});
}

# DELETED
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($archive_id);
		
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_delete_archive', sub {	(undef, $archive_id) = @_;	});
		
		$J->process_line("A\t$data->{time}\tDELETED\t$data->{archive_id}\t$relfilename");
		ok($archive_id);
		ok($archive_id eq $data->{archive_id});
		is_deeply($J->{used_versions}, {'A'=>1});
}

#  RETRIEVE_JOB
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($time, $archive_id, $job_id);
		
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_retrieve_job', sub {	(undef, $time, $archive_id, $job_id) = @_;	});
		
		$J->process_line("A\t$data->{time}\tRETRIEVE_JOB\t$data->{archive_id}\t$data->{job_id}");
		
		ok($time && $archive_id && $job_id);
		ok($time == $data->{time});
		ok($archive_id eq $data->{archive_id});
		ok($job_id eq $data->{job_id});
		is_deeply($J->{used_versions}, {'A'=>1});
}


#
# Test parsing line of Journal version '0'
#

# CREATED
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($args);
		
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_add_filename', sub {	(undef, $args) = @_;	});
		
		$J->process_line("$data->{time} CREATED $data->{archive_id} $data->{size} $data->{treehash} $relfilename");
		$J->_index_archives_as_files();
		ok($args);
		ok( $args->{$_} eq $data->{$_}, $_) for qw/archive_id size time treehash/;
		ok( $J->absfilename($args->{relfilename}) eq File::Spec->rel2abs($relfilename, $rootdir));
		
		is_deeply($J->{used_versions}, {'0'=>1});
}

# DELETED
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($archive_id);
		
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_delete_archive', sub {	(undef, $archive_id) = @_;	});
		
		$J->process_line("$data->{time} DELETED $data->{archive_id} $relfilename");
		ok($archive_id);
		ok($archive_id eq $data->{archive_id});
		is_deeply($J->{used_versions}, {'0'=>1});
}

#  RETRIEVE_JOB
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($time, $archive_id, $job_id);
		
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_retrieve_job', sub {	(undef, $time, $archive_id, $job_id) = @_;	});
		
		$J->process_line("$data->{time} RETRIEVE_JOB $data->{archive_id}");
		
		ok($time && $archive_id);
		ok($time == $data->{time});
		ok($archive_id eq $data->{archive_id});
		ok(! defined $job_id);
		is_deeply($J->{used_versions}, {'0'=>1});
}

1;

