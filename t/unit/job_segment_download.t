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
use Test::More tests => 376;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use App::MtAws::SegmentDownloadJob;
use TestUtils;
use constant ONE_MB => 1024*1024;
use Carp;
use Data::Dumper;

warning_fatal();


my $data = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	job_id => "HdGDbije6lWPT8Q8S3uOWJF6777MWRlrfMGDr688888888888zwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	'time' => 1355666755,
	mtime => 1355566755,
	relfilename => 'def/abc_bije6lWPT8Q8S3uOWJF6777MWRlrfMGDr688', # unexistant for sure, just in case utime() will work
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
};

my $segment_size = 16;

for my $size_d (-3*ONE_MB, -2*ONE_MB, -1*ONE_MB, -3, -2, -1, 0, 1, 2, 3, ONE_MB, 2*ONE_MB, 3*ONE_MB) {
	my $size = 64*ONE_MB + $size_d;
	my $job = App::MtAws::SegmentDownloadJob->new(
		archive => {
			archive_id => $data->{archive_id},
			mtime => $data->{mtime},
			size => $size,
			relfilename => $data->{relfilename},
			filename => $data->{relfilename},
		},
		file_downloads => {
			'segment-size' => $segment_size,
		}
	);
	$job->{tempfile} = 1;
	
	my $next_position = 0;
	my $is_last = 0;
	while() {
		my ($code, $t) = $job->get_task();
		if ($code eq 'ok') {
			cmp_deeply $t->{data}, superhashof({
				archive_id => $data->{archive_id}, relfilename => $data->{relfilename},
				filename => $data->{relfilename}, mtime => $data->{mtime}, jobid => $data->{jobid},
				position => $next_position
			});
			is $t->{id}, $next_position;
			is $t->{action}, "segment_download_job";
			is $t->{data}{position}, $next_position;
			ok $t->{data}{position} <= $size - 1;
			ok !$is_last;
			$is_last = 1 if $t->{data}{download_size} != $segment_size*ONE_MB;
			$next_position = $t->{data}{position} + $t->{data}{download_size};
		} elsif ($code eq 'wait') {
			ok $is_last || $size % $segment_size*ONE_MB == 0;
			is $next_position, $size;
			last;
		} else {
			confess;
		}
	}
}

{
	my $size = 64*ONE_MB + 2;
	my $job = App::MtAws::SegmentDownloadJob->new(
		archive => {
			archive_id => $data->{archive_id},
			size => $size,
			filefilename => $data->{relfilename},
			filename => $data->{relfilename},
		},
		file_downloads => {
			'segment-size' => $segment_size,
		}
	);
	$job->{tempfile} = 1;
	
	my @tasks;
	while() {
		my ($code, $t) = $job->get_task();
		if ($code eq 'ok') {
			push @tasks, $t;
		} elsif ($code eq 'wait') {
			last;
		} else {
			confess;
		}
	}
	
	my $last_task = shift @tasks;
	
	no warnings 'redefine';
	my $original = \&App::MtAws::SegmentDownloadJob::do_finish;
	local *App::MtAws::SegmentDownloadJob::do_finish = sub { confess "unexpected finish" };
	$job->finish_task($_) for @tasks;
	local *App::MtAws::SegmentDownloadJob::do_finish = sub { ok 1, "finish_task should work"; };
	my ($code) = $job->finish_task($last_task);
}

{
	my $size = 64*ONE_MB + 2;
	my $job = App::MtAws::SegmentDownloadJob->new(
		archive => {
			archive_id => $data->{archive_id},
			size => $size,
			filefilename => $data->{relfilename},
			filename => $data->{relfilename},
		},
		file_downloads => {
			'segment-size' => $segment_size,
		}
	);
	$job->{tempfile} = 1;
	
	no warnings 'redefine';
	my $finished = 0;
	my $original = \&App::MtAws::SegmentDownloadJob::do_finish;
	local *App::MtAws::SegmentDownloadJob::do_finish = sub { $finished = 1; };
	while() {
		my ($code, $t) = $job->get_task();
		if ($code eq 'ok') {
			my ($c) = $job->finish_task($t);
			if ($finished) {
				ok 1;
				last;
			}
		} else {
			confess;
		}
	}
}

1;

