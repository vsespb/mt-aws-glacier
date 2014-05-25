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

use 5.008008; # minumum perl version is 5.8.8
use TAP::Harness;
use strict;
use warnings;
use utf8;
use FindBin;
use Config;

# build requirements
use JSON::XS ();
use Test::Deep ();
use Test::Simple ();
use File::Temp ();
use Test::More ();
use Test::MockModule ();
use LWP::UserAgent ();
use DateTime ();
use Test::Spec ();
use MIME::Base64;
# for 5.8.x stock perl
use Digest::SHA ();
# /build requirements

my $testplan = 99;

my $harness = TAP::Harness->new({
    formatter_class => 'TAP::Formatter::Console',
    ($ENV{MT_COVER}) ? (switches => $ENV{MT_COVER}) : (exec => [$Config{'perlpath'}]),
    merge           => 1,
    color           => 1,
    jobs			=> 8,
});

my $priotity = qr!integration/t_treehash\.t!;
my @all = map { glob("$FindBin::RealBin/t/$_/*.t") } qw!libtest integration integration/queue_job unit unit/queue_job unit/glacier!;

die "We have ".scalar @all." tests, instead of $testplan" unless @all == $testplan;

my @first = grep { $_ =~ $priotity } @all;
my @others = grep { $_ !~ $priotity } @all;
die unless scalar @first + scalar @others == scalar @all;
die unless $harness->runtests(@first, @others)->get_status eq 'PASS';
