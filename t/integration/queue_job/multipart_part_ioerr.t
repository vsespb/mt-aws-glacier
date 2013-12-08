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
use Test::More tests => 5;
use Test::Deep;
use FindBin;
use POSIX;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};

use App::MtAws::Exceptions;
use TestUtils;

warning_fatal();

my $mtroot = get_temp_dir();
my $relfilename = 'multipart_part';
my $filename = "$mtroot/$relfilename";

BEGIN{ no warnings 'once'; *CORE::GLOBAL::read=sub(*\$$;) { $!=2; undef };};
use App::MtAws::QueueJob::MultipartPart;


sub create
{
	my ($file, $content) = @_;
	open F, ">", $file;
	print F $content if defined $content;
	close F;

}

create($filename, 'x');

open my $f, "<", $filename or die;
my $j = bless { fh => $f, position => 0, partsize => 1, th => bless { mock => 'global'}, 'App::MtAws::TreeHash' },
	'App::MtAws::QueueJob::MultipartPart';

my $expect_err = get_errno(POSIX::strerror(2));
ok ! eval { $j->read_part(); 1; };
my $err = $@;

is $err->{code}, 'cannot_read_from_file';
is $err->{errno_code}, 2;
is $err->{errno}, $expect_err;
is exception_message($err), "Cannot read from file errno=".$expect_err;


1;
