#!/usr/bin/perl

use strict;
use warnings;
use Test::Simple tests => 3;

use utf8;
use bytes;
no bytes;
my $str = "Тест";

ok ( length($str) == 4);
ok ( bytes::length($str) == 8);
ok (utf8::is_utf8($str));

1;
