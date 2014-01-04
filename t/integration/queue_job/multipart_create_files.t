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
use Test::More tests => 32;
use Test::Deep;
use FindBin;
use POSIX;
use File::stat;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJob::MultipartCreate;
use App::MtAws::Exceptions;
use TestUtils;
use App::MtAws::Utils;
use Encode;
use utf8;

warning_fatal();

use Data::Dumper;


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

{
	create($filename, 'abc');
	my $job = App::MtAws::QueueJob::MultipartCreate->new(filename => $filename, relfilename => $relfilename, partsize => 2);
	$job->init_file();
	is $job->{mtime}, stat($filename)->mtime;
	unlink $filename;
}

SKIP: {
	skip "Test cannot be performed on character-oriented filesystem", 3 unless can_work_with_non_utf8_files;

	my $filename = "тест42";
	my $fullfilename = "$mtroot/$filename";
	my $koi_filename = encode("KOI8-R", $fullfilename);
	create($koi_filename, 'abc');
	ok !-e $fullfilename;
	local $App::MtAws::Utils::_filename_encoding = 'KOI8-R';
	is get_filename_encoding, 'KOI8-R', "assume encoding is set";
	my $job = App::MtAws::QueueJob::MultipartCreate->new(filename => $fullfilename, relfilename => $relfilename, partsize => 2);
	$job->init_file();
	is $job->{mtime}, stat($koi_filename)->mtime;
	unlink $koi_filename;
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
	create($filename, 'x');

	for my $partsize_mb (1, 2, 4) {
		my $partsize = $partsize_mb*1024*1024;
		my $edge_size = $partsize*10_000;

		for my $size ($edge_size - 100, $edge_size - 1, $edge_size, $edge_size + 1, $edge_size + 27) {
			my $job = App::MtAws::QueueJob::MultipartCreate->new(filename => $filename, relfilename => $relfilename, partsize => $partsize);
			no warnings 'redefine';
			local *App::MtAws::QueueJob::MultipartCreate::file_size = sub { $size };

			if ($size > $edge_size) {
				ok ! eval { $job->init_file(); 1 };
				my $err = $@;
				cmp_deeply $err, superhashof { code => 'too_many_parts',
					message => "With current partsize=%d partsize%MiB we will exceed 10000 parts limit for the file %string filename% (file size %size%)",
					partsize => $partsize, filename => $filename, size => $size
				};
			} else {
				ok eval { $job->init_file(); 1 };
			}

		}
	}

	unlink $filename;
}


{
	my $job = App::MtAws::QueueJob::MultipartCreate->new(stdin => 1, relfilename => $relfilename, partsize => 2);
	$job->init_file();
	cmp_deeply $job->{fh}, *STDIN;
	ok abs(time() - $job->{mtime}) < 10; # test that mtime is current time
}

1;
