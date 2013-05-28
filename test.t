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

use TAP::Harness;
use strict;
use warnings;
use utf8;
use FindBin;

# build requirements
use JSON::XS ();
use Test::Deep ();
use Test::MockModule ();
use LWP::UserAgent ();
use DateTime ();
use Test::Spec ();
use LWP::Protocol::https ();
use MIME::Base64 3.11;
# for 5.8.x stock perl
use Digest::SHA ();
# /build requirements

my $harness = TAP::Harness->new({
    formatter_class => 'TAP::Formatter::Console',
    ($ARGV[0] && $ARGV[0] eq 'cover') ? (switches	=> '-MDevel::Cover') : (exec => ['perl']),
    merge           => 1,
   #verbosity       => 1,
    normalize       => 1,
    color           => 1,
    jobs			=> 8,
});

my $priotity = qr!integration/t_treehash\.t!;
my @all = (glob("$FindBin::RealBin/t/unit/*.t"), glob("$FindBin::RealBin/t/integration/*.t"));

my @first = grep { $_ =~ $priotity } @all;
my @others = grep { $_ !~ $priotity } @all;
die unless scalar @first + scalar @others == scalar @all;
$harness->runtests(@first, @others);
