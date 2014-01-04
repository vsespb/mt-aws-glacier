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
use Test::More tests => 53;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use UploadMultipartTest;
use QueueHelpers;
use App::MtAws::TreeHash;
use App::MtAws::QueueJobResult;
use TestUtils;

warning_fatal();

use Data::Dumper;

# test args validation
my %opts = (filename => '/path/somefile', relfilename => 'somefile', partsize => 1024*1024, stdin=>1);

{
	ok eval { App::MtAws::QueueJob::UploadMultipart->new( map { $_ => $opts{$_} } qw/filename relfilename partsize delete_after_upload/); 1; };

	# check for zero
	ok eval { App::MtAws::QueueJob::UploadMultipart->new((map { $_ => $opts{$_} } qw/relfilename partsize/), filename => 0); 1; };
	ok eval { App::MtAws::QueueJob::UploadMultipart->new((map { $_ => $opts{$_} } qw/filename partsize/), relfilename => 0); 1; };
	ok !eval { App::MtAws::QueueJob::UploadMultipart->new((map { $_ => $opts{$_} } qw/filename relfilename/), partsize => 0); 1; };

	ok !eval { App::MtAws::QueueJob::UploadMultipart->new( map { $_ => $opts{$_} } qw/relfilename partsize/); 1; };
	ok !eval { App::MtAws::QueueJob::UploadMultipart->new( map { $_ => $opts{$_} } qw/filename partsize/); 1; };
	ok !eval { App::MtAws::QueueJob::UploadMultipart->new( map { $_ => $opts{$_} } qw/filename relfilename/); 1; };

	# stdin stuff
	{
		my %o = map { $_ => $opts{$_} } qw/filename relfilename partsize stdin/;
		for (qw/stdin filename/) {
			local $o{$_}; delete $o{$_}; # perl 5.8/10 compat.
			ok eval { App::MtAws::QueueJob::UploadMultipart->new(%o); 1; };
		}
		{
			ok ! eval { App::MtAws::QueueJob::UploadMultipart->new(%o); 1; };
			like "$@", qr/filename xor stdin/;
		}
		{
			delete $o{stdin};
			delete $o{filename};
			ok ! eval { App::MtAws::QueueJob::UploadMultipart->new(%o); 1; };
			like "$@", qr/filename xor stdin/;
		}
	}
}


{
	# TODO: also test that it works with mtime=0
	my ($mtime, $partsize, $relfilename, $upload_id) = (123456, 2*1024*1024, 'somefile', 'someid');
	my $j = App::MtAws::QueueJob::UploadMultipart->new(filename => '/somedir/somefile', relfilename => $relfilename, partsize => $partsize );
	UploadMultipartTest::expect_upload_multipart($j, $mtime, $partsize, $relfilename, $upload_id, expect_stdin => 0);
	expect_done($j);
}

{
	my ($mtime, $partsize, $relfilename, $upload_id) = (123456, 2*1024*1024, 'somefile', 'someid');
	my $j = App::MtAws::QueueJob::UploadMultipart->new(stdin => 1, relfilename => $relfilename, partsize => $partsize );
	UploadMultipartTest::expect_upload_multipart($j, $mtime, $partsize, $relfilename, $upload_id, expect_stdin => 1);
	expect_done($j);
}

1;
