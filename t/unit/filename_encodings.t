#!/usr/bin/perl

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
use Test::More tests => 26;
use Encode;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";

use App::MtAws::Utils;
use TestUtils;

warning_fatal();


is get_filename_encoding(), 'UTF-8', "default filename encoding should be UTF-8";
for (undef, 0, ''){
	local $App::MtAws::Utils::_filename_encoding = $_;
	ok ! eval { get_filename_encoding(); 1 }, "get_filename_encoding() should confess if no filename_encoding";
	ok ! eval { binaryfilename("abc"); 1 }, "binaryfilename() should confess if no filename_encoding";
	ok ! eval { characterfilename("abc"); 1 }, "characterfilename() should confess if no filename_encoding";
}

for my $encoding ('UTF-8', 'KOI8-R') {
	local $App::MtAws::Utils::_filename_encoding = $encoding;
	my $s = "тест";
	my $s_b = encode($encoding, $s);
	ok !utf8::is_utf8($s_b);
	isnt $s_b, $s;
	is binaryfilename($s), $s_b, "binaryfilename should work for encoding $encoding";
}

{
	local $App::MtAws::Utils::_filename_encoding = 'UTF-8';
	my $s = "µµµ";
	ok utf8::is_utf8($s), "assume it's upgraded latin1 string";
	my $s_b = encode('UTF-8', $s);
	ok !utf8::is_utf8($s_b);
	isnt $s_b, $s;
	is binaryfilename($s), $s_b, "binaryfilename should work for encoding Latin-1 strings";
}

{
	local $App::MtAws::Utils::_filename_encoding = 'UTF-8';
	my $s = "µµµ";
	ok utf8::is_utf8($s), "assume it's upgraded latin1 string";
	my $s_b = encode('UTF-8', $s);
	ok !utf8::is_utf8($s_b), "assume s_b is byte string";
	isnt $s_b, $s, "assume s_b is byte string";
	my $s_d = $s;
	utf8::downgrade($s_d);
	is $s_d, $s, "assume s_d is downgraded string";
	ok !utf8::is_utf8($s_d), "assume s_d is downgraded string";
	is binaryfilename($s_d), $s_b, "binaryfilename should work for encoding Latin-1 downgraded strings";
}

1;
