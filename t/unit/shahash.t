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
use Test::More tests => 261;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::SHAHash qw/large_sha256_hex/;
use Digest::SHA qw/sha256_hex/;

local $SIG{__WARN__} = sub {die "Termination after a warning: $_[0]"};

{
	local $Digest::SHA::VERSION = '5.47';
	for my $chunksize (0..7) {
		for my $messagesize (0..$chunksize*4+1) {
			my $letter = 'A';
			my $message = join('', map { $letter++ } 1..$messagesize);
			my $original_message = $message;
			my $expected = sha256_hex($message);
			my $got = large_sha256_hex($message, $chunksize);
			is $message, $original_message;
			is $got, $expected, "$chunksize, $messagesize";
		}
	}
}

{
	no warnings 'redefine';
	{
		local $Digest::SHA::VERSION = '5.47';
		local *Digest::SHA::sha256_hex = sub { die };
		is large_sha256_hex('A', 1), "559aead08264d5795d3909718cdd05abd49572e84fe55590eef31a88a08fdffd";
	}
	{
		local $Digest::SHA::VERSION = '5.63';
		local *Digest::SHA::sha256_hex = sub { "mock1" };
		is large_sha256_hex('A', 1), "mock1";
	}
	{
		local $Digest::SHA::VERSION = '5.47';
		local *Digest::SHA::sha256_hex = sub { "mock1" };
		local *App::MtAws::SHAHash::_length = sub { 256*1024*1024 };
		is large_sha256_hex('A'), "mock1";
	}
	{
		local $Digest::SHA::VERSION = '5.47';
		local *Digest::SHA::sha256_hex = sub { "mock1" };
		local *App::MtAws::SHAHash::_length = sub { 256*1024*1024+1 };
		local *Digest::SHA::new = sub { die "Caught\n" };
		ok ! eval { large_sha256_hex('A') };
		like "$@", qr/Caught/;
	}
}


1;
