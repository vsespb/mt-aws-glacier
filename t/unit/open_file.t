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
use Test::More tests => 20;
use Test::Deep;
use Encode;
use lib qw{../lib ../../lib};
use App::MtAws::Utils;
use App::MtAws::Exceptions;

my $mtroot = '/tmp/mt-aws-glacier-tests';
my $tmp_file = "$mtroot/open_file_test";

ok ! defined eval { open_file($tmp_file); 1};
ok $@ =~ /Argument "mode" is required/;

ok ! defined eval { open_file($tmp_file, mode => 'x'); 1};
ok $@ =~ /unknown mode/;

ok defined eval { open_file($tmp_file, mode => '>', binary => 1); 1};
ok ! defined eval { open_file($tmp_file, mode => '>', binary => 1, zz => 123); 1};
ok $@ =~ /Unknown argument/;

ok ! defined eval { open_file($tmp_file, mode => '>', binary => 1, not_empty => 1); 1};
ok $@ =~ /not_empty can be used in read mode only/;

ok ! defined eval { open_file($tmp_file, mode => '>', binary => 1, file_encoding => 'UTF-8'); 1};
ok $@ =~ /cannot use binary and file_encoding at same time/;

ok ! defined eval { open_file($tmp_file, mode => '>'); 1};
ok $@ =~ /there should be file encoding or 'binary'/;

unlink $tmp_file;
ok ! defined eval { open_file($tmp_file, mode => '<', binary => 1); 1};
ok is_exception('file_open_error');
ok length(get_exception->{errno}) > 4; # crossplatform
ok get_exception->{errno}+0 > 0; # crossplatform
is get_exception->{filename}, $tmp_file;

ok defined eval { open_file($tmp_file, mode => '>', binary => 1); 1};
unlink $tmp_file;
ok defined eval { open_file($tmp_file, mode => '>', binary => 1, should_exist => 1); 1};
unlink $tmp_file;

unlink $tmp_file;


1;

