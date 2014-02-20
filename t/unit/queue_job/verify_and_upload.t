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
use Test::More tests => 125;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::VerifyAndUpload;
use VerifyTest;
use UploadMultipartTest;
use DeleteTest;
use QueueHelpers;



use Data::Dumper;

my %opts = (filename => '/path/somefile', relfilename => 'somefile', treehash => 'abc', archive_id => 'def', partsize => 4*1024*1024, delete_after_upload => 1);
my @all = keys %opts;

# test args validation
{
	ok eval { App::MtAws::QueueJob::VerifyAndUpload->new( map { $_ => $opts{$_} } @all); 1; };
	for my $exclude (@all) {
		ok !eval { App::MtAws::QueueJob::VerifyAndUpload->new( map { $_ => $opts{$_} } grep { $_ ne $exclude} @all); 1; }, $exclude;
	}
	for my $zero (qw/filename relfilename/) {
		ok eval { App::MtAws::QueueJob::VerifyAndUpload->new( (map { $_ => $opts{$_} } grep { $_ ne $zero} @all), $zero => 0); 1; }, $zero;
	}
	ok eval { App::MtAws::QueueJob::VerifyAndUpload->new( (map { $_ => $opts{$_} } qw/filename relfilename treehash partsize/), delete_after_upload => 0); 1; };
}

for (0, 1) {
	if ($_) {
		$opts{filename} = '/path/somefile';
		$opts{relfilename} = 'somefile';
	} else {
		$opts{filename} = '0';
		$opts{relfilename} = '0';
	}

	my @main_opts = (map { $_ => $opts{$_} } qw/filename relfilename treehash partsize/);
	{
		my @opts = (@main_opts, delete_after_upload => 1, archive_id => 'def');
		{
			my $j = App::MtAws::QueueJob::VerifyAndUpload->new(@opts);
			VerifyTest::expect_verify($j, $opts{filename}, $opts{relfilename}, $opts{treehash}, verify_value => 1);
			expect_done($j);
		}

		{
			my $j = App::MtAws::QueueJob::VerifyAndUpload->new(@opts);
			VerifyTest::expect_verify($j, $opts{filename}, $opts{relfilename}, $opts{treehash}, verify_value => 0);
			UploadMultipartTest::expect_upload_multipart($j, 123, $opts{partsize}, $opts{relfilename}, 'xyz');
			DeleteTest::expect_delete($j, $opts{relfilename}, $opts{archive_id});
			expect_done($j);
		}
	}
	{
		my @opts = (@main_opts, delete_after_upload => 0);
		{
			my $j = App::MtAws::QueueJob::VerifyAndUpload->new(@opts);
			VerifyTest::expect_verify($j, $opts{filename}, $opts{relfilename}, $opts{treehash}, verify_value => 1);
			expect_done($j);
		}

		{
			my $j = App::MtAws::QueueJob::VerifyAndUpload->new(@opts);
			VerifyTest::expect_verify($j, $opts{filename}, $opts{relfilename}, $opts{treehash}, verify_value => 0);
			UploadMultipartTest::expect_upload_multipart($j, 123, $opts{partsize}, $opts{relfilename}, 'xyz');
			expect_done($j);
		}
	}
}

# test dry-run

{
	my $j = App::MtAws::QueueJob::VerifyAndUpload->new( map { $_ => $opts{$_} } @all);
	is $j->will_do(), "Will VERIFY treehash and UPLOAD $opts{filename} if modified";;
}

1;
