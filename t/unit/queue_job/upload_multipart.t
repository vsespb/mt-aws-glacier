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
use Test::More tests => 14;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../../", "$FindBin::RealBin/../../lib/", "$FindBin::RealBin/../../../lib";
use UploadMultipartTest;
use App::MtAws::TreeHash;
use App::MtAws::QueueJobResult;
use TestUtils;

warning_fatal();

use Data::Dumper;

{
	# TODO: also test that it works with mtime=0
	my ($mtime, $partsize, $relfilename, $upload_id) = (123456, 2*1024*1024, 'somefile', 'someid');
	my $j = App::MtAws::QueueJob::UploadMultipart->new(filename => '/somedir/somefile', relfilename => $relfilename, partsize => $partsize );
	UploadMultipartTest::expect_upload_multipart($j, $mtime, $partsize, $relfilename, $upload_id);
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);
}

1;
