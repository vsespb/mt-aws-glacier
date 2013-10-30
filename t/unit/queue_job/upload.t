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
use Test::More tests => 39;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../../", "$FindBin::RealBin/../../lib/", "$FindBin::RealBin/../../../lib";

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Upload;
use UploadMultipartTest;
use TestUtils;

warning_fatal();

sub test_coderef { code sub { ref $_[0] eq 'CODE' } }

use Data::Dumper;

my %opts = (filename => '/path/somefile', relfilename => 'somefile', delete_after_upload => 0, partsize => 1024*1024);
my $mtime = 123456;
my $upload_id = "someuploadid";

# test args validation
{
	ok eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename relfilename partsize delete_after_upload/); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename relfilename partsize/); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename relfilename delete_after_upload/); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/filename partsize delete_after_upload/); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new( map { $_ => $opts{$_} } qw/relfilename partsize delete_after_upload/); 1; };

	ok eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename relfilename partsize/), delete_after_upload =>1, archive_id => 'abc' ); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename relfilename partsize/), delete_after_upload =>1 ); 1; };
	ok !eval { App::MtAws::QueueJob::Upload->new((map { $_ => $opts{$_} } qw/filename relfilename partsize/), delete_after_upload =>0, archive_id => 'abc' ); 1; };
}

{
	my ($mtime, $partsize, $relfilename, $upload_id) = (123456, 2*1024*1024, 'somefile', 'someid');
	my $j = App::MtAws::QueueJob::Upload->new(filename => '/somedir/somefile', relfilename => $relfilename, partsize => $partsize, delete_after_upload =>0 );
	UploadMultipartTest::expect_upload_multipart($j, $mtime, $partsize, $relfilename, $upload_id);
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);
}

{
	my ($mtime, $partsize, $relfilename, $upload_id) = (123456, 2*1024*1024, 'somefile', 'someid');
	my $j = App::MtAws::QueueJob::Upload->new(filename => '/somedir/somefile', relfilename => $relfilename, partsize => $partsize, delete_after_upload =>1, archive_id => 'abc' );
	UploadMultipartTest::expect_upload_multipart($j, $mtime, $partsize, $relfilename, $upload_id, is_finished => 0);
	cmp_deeply my $res = $j->next,
		App::MtAws::QueueJobResult->full_new(
			task => {
				args => {
					relfilename => $relfilename,
					archive_id => 'abc',
				},
				action => 'delete_archive',
				cb => test_coderef,
				cb_task_proxy => test_coderef,
			},
			code => JOB_OK,
		);
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
	$res->{task}{cb_task_proxy}->();
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);
}

1;

__END__
