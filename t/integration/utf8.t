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
use Test::Simple tests => 45;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils;
use Encode;
use App::MtAws::Utils;

warning_fatal();

use utf8;
use bytes;
no bytes;
my $str = "Тест";

ok ( length($str) == 4);
ok ( bytes::length($str) == 8);
ok (utf8::is_utf8($str));

use utf8;

for my $sample ("µ", "Ф", "Xµ", "XФ", "µФ", "XµФ") { # mix of ASCII, Unicode (128..255) and Unicode > 255 chars
	ok utf8::is_utf8($sample);
	ok is_wide_string($sample );
	ok !is_wide_string(encode("UTF-8", $sample ));
	try_drop_utf8_flag $sample;
	ok utf8::is_utf8($sample);

	my ($ascii, undef) = split(';', "abcdef;$sample");
	ok utf8::is_utf8($ascii);
	ok !is_wide_string($ascii);
	try_drop_utf8_flag $ascii;
	ok !utf8::is_utf8($ascii);
}

1;
