#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use lib qw/../;
use LineProtocol;
use Test::Simple tests => 3;

my $str = "Тест";

ok (decode_data(encode_data($str)) eq $str);
ok (utf8::is_utf8 decode_data(encode_data($str)) );
ok (length(decode_data(encode_data($str))) == 4 );


1;
