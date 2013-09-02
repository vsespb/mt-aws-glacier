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
use utf8;
use Test::More tests => 5;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Job::FileCreate;
use App::MtAws::Exceptions;
use File::Path;
use Data::Dumper;
use POSIX;
use TestUtils;

warning_fatal();

my $mtroot = get_temp_dir();
my $file = "$mtroot/job_file_create";

chmod 0744, $file;
unlink $file;

{
	create($file, '');
	my $job = App::MtAws::Job::FileCreate->new(filename => $file, relfilename => 'job_file_create', partsize => 2);
	ok ! defined eval { $job->get_task(); 1; };
	my $err = $@;
	cmp_deeply $err, superhashof { code => 'file_is_zero',
		message => "File size is zero (and it was not when we read directory listing). Filename: %string filename%",
		filename => $file };
	unlink $file;
}

SKIP: {
	skip "Cannot run under root", 3 if is_posix_root;

	create($file, 'x');
	chmod 0000, $file;
	my $job = App::MtAws::Job::FileCreate->new(filename => $file, relfilename => 'job_file_create', partsize => 2);
	ok ! defined eval { $job->get_task(); 1; };
	my $err = $@;
	cmp_deeply $err, superhashof { code => 'upload_file_open_error',
		message => "Unable to open task file %string filename% for reading, errno=%errno%",
		filename => $file };

	is $err->{errno}, get_errno(POSIX::strerror(EACCES));
	chmod 0744, $file;
	unlink $file;
}

chmod 0744, $file;
unlink $file;


sub create
{
	my ($file, $content) = @_;
	open F, ">", $file;
	print F $content if defined $content;
	close F;

}

1;
