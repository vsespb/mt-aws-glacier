#!/usr/bin/env perl

# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2014  Victor Efimov
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
use Test::More tests => 11;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::Journal;



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


my $J;

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, $data->{job_id});
	cmp_deeply $J->{active_retrievals}, { $data->{archive_id} => { job_id => $data->{job_id}, time => $data->{time} }}, "should work";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
	$J->{last_read_time} = $data->{'time'} + 10;
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, $data->{job_id});
	ok !defined $J->{active_retrievals}, "should not work when use_active_retrievals not in use";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, $data->{job_id});
	$J->_retrieve_job($data->{'time'}+3, $data->{archive_id}, $data->{job_id});
	cmp_deeply $J->{active_retrievals}, { $data->{archive_id} => { job_id => $data->{job_id}, time => $data->{time}+3 }}, "should replace with latest";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;
	$J->_retrieve_job($data->{'time'}+3, $data->{archive_id}, $data->{job_id});
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, $data->{job_id});
	cmp_deeply $J->{active_retrievals}, { $data->{archive_id} => { job_id => $data->{job_id}, time => $data->{time}+3 }}, "should replace with latest if order is different";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;
	$J->_retrieve_job($data->{'time'}+2, $data->{archive_id}, $data->{job_id});
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, $data->{job_id});
	$J->_retrieve_job($data->{'time'}+3, $data->{archive_id}, $data->{job_id});
	cmp_deeply $J->{active_retrievals}, { $data->{archive_id} => { job_id => $data->{job_id}, time => $data->{time}+3 }}, "should replace with latest if order is different";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, 'job1');
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, 'job2');
	cmp_deeply $J->{active_retrievals}, { $data->{archive_id} => { job_id => 'job1', time => $data->{time} }}, "should not replace if same time";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;
	$J->_retrieve_job($data->{'time'}, 'archiveid1', 'job1');
	$J->_retrieve_job($data->{'time'}+1, 'archiveid2', 'job2');
	cmp_deeply $J->{active_retrievals},
		{ 'archiveid1' => { job_id => 'job1', time => $data->{time} }, 'archiveid2' => { job_id => 'job2', time => $data->{time}+1 }}, "should work with two archives";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;
	$J->_retrieve_job($data->{'time'}, 'archiveid1', 'job1');
	$J->_retrieve_job($data->{'time'}, 'archiveid2', 'job2');
	cmp_deeply $J->{active_retrievals},
		{ 'archiveid1' => { job_id => 'job1', time => $data->{time} }, 'archiveid2' => { job_id => 'job2', time => $data->{time} }}, "should work with two archives when time same";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 24*60*60 -1;
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, $data->{job_id});
	cmp_deeply $J->{active_retrievals},
		{ $data->{archive_id} => { job_id => $data->{job_id}, time => $data->{time} }}, "should work if difference is 24h - 1 second";

	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{active_retrievals} = {};
	$J->{last_read_time} = $data->{'time'} + 24*60*60;
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, $data->{job_id});
	cmp_deeply $J->{active_retrievals}, {}, "should not work if difference is 24h";
		
	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{active_retrievals} = {};
	$J->{last_read_time} = $data->{'time'} + 24*60*60 + 1;
	$J->_retrieve_job($data->{'time'}, $data->{archive_id}, $data->{job_id});
	cmp_deeply $J->{active_retrievals}, {}, "should not work if difference is 24h + 1 second";
		
# TODO: integration tests between _retrieve_job and process_line
# TODO: unit test of read_journal
1;

