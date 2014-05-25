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
use Test::More tests => 256;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::SHAHash qw/large_sha256_hex/;
use Digest::SHA qw/sha256_hex/;

local $SIG{__WARN__} = sub {die "Termination after a warning: $_[0]"};

{
	for my $chunksize (0..7) {
		for my $messagesize (0..$chunksize*4+1) {
			my $letter = 'A';
			my $message = join('', map { $letter++ } 1..$messagesize);
			my $original_message = $message;
			my $got = large_sha256_hex($message, $chunksize);
			my $expected = sha256_hex($message);
			is $message, $original_message;
			is $got, $expected, "$chunksize, $messagesize";
		}
	}
}


1;
