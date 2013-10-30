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
use Test::More tests => 19;
use Encode;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::Utils;
use Encode;
use TestUtils;

warning_fatal();

my $utfprefix = "(UTF-8)";

# control chars

is hex_dump_string("hello"), '"hello"';
is hex_dump_string("hello\n"), '"hello\\n"';
is hex_dump_string("hello\r"), '"hello\\r"';
is hex_dump_string("hello\r\n"), '"hello\\r\\n"';
is hex_dump_string("\nhello\n\n"), '"\\nhello\\n\\n"';
is hex_dump_string("hello\t"), '"hello\t"';


is hex_dump_string("\thello\t"), '"\\thello\t"', "regexp should replace multiple times";

is hex_dump_string("тест"), "$utfprefix \"\\xD1\\x82\\xD0\\xB5\\xD1\\x81\\xD1\\x82\"";
is hex_dump_string("тест test"), "$utfprefix \"\\xD1\\x82\\xD0\\xB5\\xD1\\x81\\xD1\\x82 test\"";
is hex_dump_string("тест\ttest"), "$utfprefix \"\\xD1\\x82\\xD0\\xB5\\xD1\\x81\\xD1\\x82\\ttest\"";
is hex_dump_string(encode("UTF-8", "тест")), "\"\\xD1\\x82\\xD0\\xB5\\xD1\\x81\\xD1\\x82\"";

is hex_dump_string("\x1e"), '"\\x1E"';

is hex_dump_string("\\"), '"\\\\"';
is hex_dump_string("\\A\\"), '"\\\\A\\\\"';
is hex_dump_string("\\\\"), '"\\\\\\\\"';

{
	my $str = "test!";
	Encode::_utf8_on $str;
	ok utf8::is_utf8($str);
	is hex_dump_string($str), "\"$str\"";
}

{
	# broken UTF-8
	my $binstr = "\xD1\xD2";
	ok ! defined eval { decode("UTF-8", $binstr, Encode::FB_CROAK|Encode::LEAVE_SRC) }, "our UTF example should be broken";
	my $str = $binstr;
	Encode::_utf8_on($str);
	is hex_dump_string($str), "$utfprefix \"\\xD1\\xD2\"";
}


1;

