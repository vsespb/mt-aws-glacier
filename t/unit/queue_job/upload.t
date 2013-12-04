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
use Test::More tests => 169;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Upload;
use UploadMultipartTest;
use DeleteTest;
use QueueHelpers;
use TestUtils;

warning_fatal();



use Data::Dumper;

my %opts = (filename => '/path/somefile', relfilename => 'somefile', delete_after_upload => 0, partsize => 1024*1024, stdin=>1);
my $mtime = 123456;
my $upload_id = "someuploadid";

# test args validation
{
	ok eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename relfilename partsize delete_after_upload/); 1; };

	# check for zero
	ok eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/relfilename partsize delete_after_upload/), filename => 0); 1; };
	ok eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename partsize delete_after_upload/), relfilename => 0); 1; };
	ok eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename relfilename partsize/), delete_after_upload => 0); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename relfilename delete_after_upload/), partsize => 0); 1; };

	ok !eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename relfilename partsize/); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename relfilename delete_after_upload/); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename partsize delete_after_upload/); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/relfilename partsize delete_after_upload/); 1; };

	ok eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename relfilename partsize/), delete_after_upload =>1, archive_id => 'abc' ); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename relfilename partsize/), delete_after_upload =>1 ); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename relfilename partsize/), delete_after_upload =>0, archive_id => 'abc' ); 1; };

	# stdin stuff
	{
		my %o = map { $_ => $opts{$_} } qw/filename relfilename partsize delete_after_upload stdin/;
		for (qw/stdin filename/) {
			local $o{$_}; delete $o{$_}; # perl 5.8/10 compat.
			ok eval { App::MtAws::QueueJob::Upload->new(%o); 1; };
		}
		{
			ok ! eval { App::MtAws::QueueJob::Upload->new(%o); 1; };
			like "$@", qr/filename xor stdin/;
		}
		{
			delete $o{stdin};
			delete $o{filename};
			ok ! eval { App::MtAws::QueueJob::Upload->new(%o); 1; };
			like "$@", qr/filename xor stdin/;
		}
	}
}

sub test_case
{
	my ($filename, $relfilename, $mtime) = @_;
	{
		my ($partsize, $upload_id) = (2*1024*1024, 'someid');
		my $j = App::MtAws::QueueJob::Upload->new(filename => $filename, relfilename => $relfilename, partsize => $partsize, delete_after_upload =>0 );
		UploadMultipartTest::expect_upload_multipart($j, $mtime, $partsize, $relfilename, $upload_id, expect_stdin => 0);
		expect_done($j);
	}

	{
		my ($partsize, $upload_id) = (2*1024*1024, 'someid');
		my $j = App::MtAws::QueueJob::Upload->new(filename => $filename, relfilename => $relfilename, partsize => $partsize, delete_after_upload =>1, archive_id => 'abc' );
		UploadMultipartTest::expect_upload_multipart($j, $mtime, $partsize, $relfilename, $upload_id, expect_stdin => 0, is_finished => 0);
		DeleteTest::expect_delete($j, $relfilename, 'abc');
		expect_done($j);
	}
}

test_case '/path/somefile', 'somefile', 123456;
test_case '/path/somefile', 'somefile', 0;
test_case '0', 0, 123456;

# test stdin
{
	my ($partsize, $upload_id) = (2*1024*1024, 'someid');
	my $j = App::MtAws::QueueJob::Upload->new(relfilename => "somefile", stdin => 1, partsize => $partsize, delete_after_upload =>0 );
	UploadMultipartTest::expect_upload_multipart($j, 12345, 2*1024*1024, "somefile", "someid", expect_stdin => 1);
	expect_done($j);
}

# test dry-run
{
	my $j = App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename relfilename partsize delete_after_upload/);
	is $j->will_do(), "Will UPLOAD $opts{filename}"
}
{
	my $j = App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/stdin relfilename partsize delete_after_upload/);
	is $j->will_do(), "Will UPLOAD stream from STDIN"
}

1;

__END__
