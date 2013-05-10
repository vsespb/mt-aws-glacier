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
use lib qw{../lib ../../lib};
use App::MtAws::LineProtocol qw/encode_data decode_data/;
use Test::More tests => 5;
use bytes;
no bytes;

my $str = "Тест";

ok (decode_data(encode_data($str)) eq $str);
ok (utf8::is_utf8 decode_data(encode_data($str)) );
ok (!utf8::is_utf8 encode_data($str) );
ok (length(decode_data(encode_data($str))) == 4 );
is (bytes::length(encode_data($str)), 26);


1;
