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
use Test::More tests => 1728;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::FileVersions;
use TestUtils;

warning_fatal();

my $cmp = \&App::MtAws::FileVersions::_cmp;
my $is_ok=1;

sub object
{
	my ($time, $mtime, $archive_id) = @_;
	{ time => $time, mtime => $mtime, ($archive_id ? (archive_id => $archive_id) : () )}; 
}

{
	my @all = (1,2,3);
	for my $t1 (@all) { for my $m1 (@all, undef) { 
	for my $t2 (@all) { for my $m2 (@all, undef) {
	for my $t3 (@all) { for my $m3 (@all, undef) {
		
		my ($x, $y, $z) = sort { $cmp->(object($a->[0], $a->[1]), object($b->[0], $b->[1])) } ( [$t1, $m1], [$t2, $m2], [$t3, $m3] );
		$is_ok=1;
		$is_ok = 0 unless $cmp->(object($x->[0], $x->[1]), object($z->[0], $z->[1])) <= 0;
		$is_ok = 0 unless $cmp->(object($x->[0], $x->[1]), object($y->[0], $y->[1])) <= 0;
		$is_ok = 0 unless $cmp->(object($y->[0], $y->[1]), object($z->[0], $z->[1])) <= 0;

		$is_ok = 0 unless $cmp->(object($z->[0], $z->[1]), object($x->[0], $x->[1])) >= 0;
		$is_ok = 0 unless $cmp->(object($y->[0], $y->[1]), object($x->[0], $x->[1])) >= 0;
		$is_ok = 0 unless $cmp->(object($z->[0], $z->[1]), object($y->[0], $y->[1])) >= 0;

		no warnings 'uninitialized';
		ok $is_ok, "comparsion function should be transitive with [$t1, $m1], [$t2, $m2], [$t3, $m3]";

	}}
	}}
	}}
}


1;

