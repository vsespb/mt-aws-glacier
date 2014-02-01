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
use Test::More tests => 3353;
use Test::Deep;
use Data::Dumper;
use Carp;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadSegments;
use QueueHelpers;
use LCGRandom;
use TestUtils;
use DownloadSegmentsTest qw/test_case_full test_case_lite test_case_random_finish ONE_MB prepare_download_segments prepare_mock/;

warning_fatal();

#
# test validation
#

{
	my %opts = (relfilename => 'somefile', archive_id => 'abc', filename => '/path/somefile', jobid => 'somejob',
		size => 123, mtime => 456, file_downloads => {'segment-size' => 2});
	
	# test args validation
	{
		ok eval { App::MtAws::QueueJob::DownloadSegments->new( %opts ); 1; };

		for my $exclude_opt (sort keys %opts) {
			ok ! eval { App::MtAws::QueueJob::DownloadSegments->new( map { $_ => $opts{$_} } grep { $_ ne $exclude_opt } keys %opts ); 1; },
				"should not work without $exclude_opt";
		}

		for my $zero_opt (qw/relfilename filename mtime/) {
			local $opts{$zero_opt} = 0;
			ok eval { App::MtAws::QueueJob::DownloadSegments->new( %opts ); 1; }, "should work with $zero_opt=0";
			
		}
	}

	for (undef, qw/relfilename filename mtime/) {
		local $opts{$_} = 0 if defined;
		my $j = App::MtAws::QueueJob::DownloadSegments->new(%opts);
		
		# TODO: move to DownloadSegmentsTest, make similar to DownloadSingleTest::expect_download_single
		prepare_mock sub {
			my $res = $j->next;
			cmp_deeply $res,
				App::MtAws::QueueJobResult->full_new(
					task => {
						args => {
							(map { $_ => $opts{$_} } qw/filename jobid relfilename archive_id tempfile/),
							download_size => code(sub{ shift > 0 }),
							position => code(sub{ defined shift }),
							tempfile => 'sometempfilename'
						},
						action => 'segment_download_job',
						cb => test_coderef,
						cb_task_proxy => test_coderef,
					},
					code => JOB_OK,
				);
		}
	}
}

my $prep = \&prepare_download_segments;

lcg_srand 467287 => sub {
	# manual testing segment sizes
	
	test_case_full $prep, ONE_MB, 1, [ONE_MB];
	test_case_full $prep, ONE_MB+1, 1, [ONE_MB, 1];
	test_case_full $prep, ONE_MB-1, 1, [ONE_MB-1];
	
	
	test_case_full $prep, 2*ONE_MB, 2, [2*ONE_MB];
	test_case_full $prep, 2*ONE_MB+1, 2, [2*ONE_MB, 1];
	test_case_full $prep, 2*ONE_MB+2, 2, [2*ONE_MB, 2];
	test_case_full $prep, 2*ONE_MB-1, 2, [2*ONE_MB-1];
	test_case_full $prep, 2*ONE_MB-2, 2, [2*ONE_MB-2];
	
	
	test_case_full $prep, 4*ONE_MB, 2, [2*ONE_MB, 2*ONE_MB];
	test_case_full $prep, 4*ONE_MB+1, 2, [2*ONE_MB, 2*ONE_MB, 1];
	test_case_full $prep, 4*ONE_MB-1, 2, [2*ONE_MB, 2*ONE_MB-1];

	# auto testing segment sizes

	for my $segment (1, 2, 8, 16) {
		for my $size (2, 3, 15) {
			if ($size*ONE_MB >= 2*$segment*ONE_MB) { # avoid some unneeded testing
				for my $delta (-30, -2, -1, 0, 1, 2, 27) {
					test_case_lite $prep, $size*ONE_MB+$delta, $segment;
					test_case_random_finish($prep, $size*ONE_MB+$delta, $segment, $_) for (1..4);
				}
			}
		}
	}
};

1;

__END__
