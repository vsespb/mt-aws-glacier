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
use Test::More tests => 28;
use Test::Deep;
use FindBin;
use POSIX;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartCreate;
use App::MtAws::Exceptions;
use QueueHelpers;
use TestUtils;

warning_fatal();

use Data::Dumper;

sub test_case
{
	my ($filename, $relfilename, $mtime, $partsize) = @_;
	no warnings 'redefine';
	local *App::MtAws::QueueJob::MultipartCreate::init_file = sub {
		$_[0]->{fh} = 'filehandle';
		$_[0]->{mtime} = $mtime;
	};
	my $j = App::MtAws::QueueJob::MultipartCreate->new(filename => $filename, relfilename => $relfilename, partsize => $partsize);
	cmp_deeply my $res = $j->next,
		App::MtAws::QueueJobResult->full_new(code => JOB_OK,
		task => { args => {partsize => $partsize, relfilename => $relfilename, mtime => $mtime},
		action => 'create_upload', cb => test_coderef, cb_task_proxy => test_coderef});
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
	expect_wait($j);
	call_callback($res, upload_id => "someuploadid");
	expect_done($j);
	is $j->{upload_id}, "someuploadid";
}

test_case('/path/somefile', 'somefile', 123456, 2*1024*1024);
test_case('/path/somefile', 'somefile', 0, 2*1024*1024);
test_case('0', '0', 123456, 2*1024*1024);

# integration tests with real FS


sub create
{
	my ($file, $content) = @_;
	open F, ">", $file;
	print F $content if defined $content;
	close F;

}

my $mtroot = get_temp_dir();
my $relfilename = 'multipart_create';
my $filename = "$mtroot/$relfilename";

chmod 0744, $filename;
unlink $filename;

{
	create($filename, '');
	my $job = App::MtAws::QueueJob::MultipartCreate->new(filename => $filename, relfilename => $relfilename, partsize => 2);
	ok ! eval { $job->init_file(); 1; };
	my $err = $@;
	cmp_deeply $err, superhashof { code => 'file_is_zero',
		message => "File size is zero (and it was not when we read directory listing). Filename: %string filename%",
		filename => $filename };
	unlink $filename;
}

SKIP: {
	skip "Cannot run under root", 3 if is_posix_root;

	create($filename, 'x');
	chmod 0000, $filename;
	my $job = App::MtAws::QueueJob::MultipartCreate->new(filename => $filename, relfilename => $relfilename, partsize => 2);
	ok ! eval { $job->init_file(); 1; };
	my $err = $@;
	cmp_deeply $err, superhashof { code => 'upload_file_open_error',
		message => "Unable to open task file %string filename% for reading, errno=%errno%",
		filename => $filename };

	is $err->{errno}, get_errno(POSIX::strerror(EACCES));
	chmod 0744, $filename;
	unlink $filename;
}

chmod 0744, $filename;
unlink $filename;


{
	my $job = App::MtAws::QueueJob::MultipartCreate->new(stdin => 1, relfilename => $relfilename, partsize => 2);
	no warnings 'redefine', 'once';
	$job->init_file();
	cmp_deeply $job->{fh}, *STDIN;
	ok abs(time() - $job->{mtime}) < 10; # test that mtime is current time
}

1;
