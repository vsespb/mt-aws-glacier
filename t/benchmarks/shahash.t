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
use utf8;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use BenchmarkTest tests => 5;
use Test::More;
use App::MtAws::SHAHash qw/large_sha256_hex/;
use Digest::SHA qw/sha256_hex/;

local $SIG{__WARN__} = sub {die "Termination after a warning: $_[0]"};

sub get_mem
{
	my (undef, $mem) = `ps -p $$ -o rss`;
	$mem / 1024;
}

sub check_mem
{
	my ($min, $max) = @_;
	my $m = get_mem();
	ok( ($m <= $max) && ($m >= $min), "memory - expected $min..$max, found $m" );
}

# constructing message with $messagesize * MB size
my $messagesize = 100;
my $chunksize = 70;

check_mem(0, 20);
my $maxoverhead = int(get_mem()) + 7;


my $onemb = 1024*1024;
my $expected_mem = undef;
{
	our $message = '';
	$message .= "x" x $onemb for (1..$messagesize);
	# / whole this stupid code needed to workaround perl memory bugs for old perl versions
	check_mem($messagesize, $messagesize + $maxoverhead);
	my $expected = sha256_hex($message);
	my $got = large_sha256_hex($message, $chunksize*$onemb);
	is $got, $expected;

	$expected_mem = $messagesize;
	$expected_mem += $chunksize if ($^V lt v5.14 && $Digest::SHA::VERSION le '5.63');

	check_mem($expected_mem, $expected_mem + $maxoverhead);
	undef $message;
}

{
	our $message = '';
	$message .= "x" x $onemb for (1..$messagesize);
	check_mem($messagesize, $expected_mem + $maxoverhead);
	undef $message;
}


1;
