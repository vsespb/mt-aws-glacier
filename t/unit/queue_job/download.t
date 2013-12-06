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
use Test::More tests => 898;
use Test::Deep;
use Data::Dumper;
use Carp;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadSegments;
use DownloadSingleTest;
use QueueHelpers;
use LCGRandom;
use TestUtils;
use DownloadSegmentsTest qw/test_case_full test_case_lite test_case_random_finish ONE_MB prepare_download/;

warning_fatal();


my $prep = \&prepare_download;

#
# test args validation
#
{
	my %opts = (relfilename => 'somefile', archive_id => 'abc', filename => '/path/somefile', jobid => 'somejob',
		size => 123, mtime => 456, treehash => 'sometreehash', file_downloads => {'segment-size' => 1 });

	ok eval { my $j = App::MtAws::QueueJob::Download->new(%opts); 1 };

	for my $exclude_opt (qw/relfilename filename archive_id file_downloads jobid size mtime treehash/) {
		ok exists $opts{$exclude_opt};
		ok ! eval { App::MtAws::QueueJob::Download->new( map { $_ => $opts{$_} } grep { $_ ne $exclude_opt } keys %opts ); 1; },
			"should not work without $exclude_opt";
	}

	for my $non_zero_opt (qw/archive_id jobid size treehash/) {
		ok exists $opts{$non_zero_opt};
		ok ! eval { App::MtAws::QueueJob::Download->new(%opts, $non_zero_opt => 0); 1; },
	}

	for my $zero_opt (qw/relfilename filename mtime/) {
		ok exists $opts{$zero_opt};
		local $opts{$zero_opt} = 0;
		ok eval { App::MtAws::QueueJob::Download->new( %opts ); 1; }, "should work with $zero_opt=0";
	}
}


# TODO: move to lib test

#
# testing how Download.pm acts like DownloadSingle
#
{
	sub test_case_single
	{
		my ($size, $segment_size) = @_;
		my %opts = (relfilename => 'somefile', archive_id => 'abc', filename => '/tmp/notapath/somefile', jobid => 'somejob',
			size => $size, mtime => 456, treehash => 'sometreehash' ); # /tmp/notapath/somefile because if code is broken, it'll try create it

		my $j = App::MtAws::QueueJob::Download->new(%opts, file_downloads => { 'segment-size' => $segment_size });
		DownloadSingleTest::expect_download_single($j, %opts);
		expect_done($j);
	}
	for my $delta (-30, -2, -1, 0) {
		test_case_single ONE_MB+$delta, 1;
		for my $factor (-1, +1) {
			next if !$delta && $factor < 0; # skip -0, we already have +0
			test_case_single ONE_MB+$delta*$factor, 2;
		}
	}
}

#
# testing how Download.pm acts like DownloadSegments
#
lcg_srand 667887 => sub {
	# manual testing segment sizes

	test_case_full $prep, ONE_MB+1, 1, [ONE_MB, 1];


	test_case_full $prep, 2*ONE_MB+1, 2, [2*ONE_MB, 1];
	test_case_full $prep, 2*ONE_MB+2, 2, [2*ONE_MB, 2];

	test_case_full $prep, 4*ONE_MB, 2, [2*ONE_MB, 2*ONE_MB];
	test_case_full $prep, 4*ONE_MB+1, 2, [2*ONE_MB, 2*ONE_MB, 1];
	test_case_full $prep, 4*ONE_MB-1, 2, [2*ONE_MB, 2*ONE_MB-1];

	# auto testing segment sizes

	for my $segment (1, 8, 16) {
		for my $size (2, 15) {
			if ($size*ONE_MB >= 2*$segment*ONE_MB) { # test only when there should be segments
				for my $delta (-2, 0, 3) {
					test_case_lite $prep, $size*ONE_MB+$delta, $segment;
					test_case_random_finish($prep, $size*ONE_MB+$delta, $segment, $_) for (1, 4);
				}
			}
		}
	}
};

1;

__END__
