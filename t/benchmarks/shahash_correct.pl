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

use lib '/home/tav/local-lib/5.014002-x86_64-linux-gnu-thread-multi/Digest-SHA-5.62/lib/perl5/x86_64-linux-gnu-thread-multi';


use strict;
use warnings;
use utf8;
use Test::More tests => 1;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::SHAHash qw/large_sha256_hex/;
use Digest::SHA qw/sha256_hex/;

local $SIG{__WARN__} = sub {die "Termination after a warning: $_[0]"};

# constructing message with $messagesize * MB size
my $messagesize = 100;
my $onemb = 1024*1024;
my $message = '';
$message .= "x" x $onemb for (1..1024);
# / whole this stupid code needed to workaround perl memory bugs for old perl versions
my $got = large_sha256_hex($message);
is $got, 'e99508f2bd8ee171c7e41eb0370907eeddf47dba62efbcf99dd25e48ee87c4c8';
1;
