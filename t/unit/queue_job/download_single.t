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
use Test::More tests => 31;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadSingle;
use DownloadSingleTest;
use QueueHelpers;



use Data::Dumper;

my %opts = (relfilename => 'somefile', archive_id => 'abc', filename => '/path/somefile', jobid => 'somejob',
	size => 123, mtime => 456, treehash => 'sometreehash');

# test args validation
{
	ok eval { App::MtAws::QueueJob::DownloadSingle->new( %opts ); 1; };
	
	for my $exclude_opt (sort keys %opts) {
		ok ! eval { App::MtAws::QueueJob::DownloadSingle->new( map { $_ => $opts{$_} } grep { $_ ne $exclude_opt } keys %opts ); 1; },
			"should not work without $exclude_opt";
	}
	
	for my $zero_opt (qw/relfilename filename mtime/) {
		local $opts{$zero_opt} = 0;
		ok eval { App::MtAws::QueueJob::DownloadSingle->new( %opts ); 1; }, "should work with $zero_opt=0";
		
	}
}

for (undef, qw/relfilename filename mtime/) {
	local $opts{$_} = 0 if defined;
	my $j = App::MtAws::QueueJob::DownloadSingle->new(%opts);
	DownloadSingleTest::expect_download_single($j, %opts);
	expect_done($j);
}



1;

