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
use Test::More tests => 5184;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::FileVersions;
use TestUtils;

warning_fatal();

my $cmp = \&App::MtAws::FileVersions::_cmp;

sub object { { time => $_[0], mtime => $_[1] } }

#
# This test tests _cmp function behaviour (like transitivity), so you can change function algorithm, but this
# test must pass anyway
#

{
	my @all = (1,2,3);
	for my $t1 (@all) { for my $m1 (@all, undef) { 
	for my $t2 (@all) { for my $m2 (@all, undef) {
	for my $t3 (@all) { for my $m3 (@all, undef) {
		
		my $f1 = object($t1, $m1);
		my $f2 = object($t2, $m2);
		my $f3 = object($t3, $m3);
		
		{
			my $is_ok = 1;
			my ($x, $y, $z) = sort { $cmp->($a, $b) } ( $f1, $f2, $f3 );
			$is_ok = 0 unless $cmp->($x, $z) <= 0;
			$is_ok = 0 unless $cmp->($x, $y) <= 0;
			$is_ok = 0 unless $cmp->($y, $z) <= 0;
	
			$is_ok = 0 unless $cmp->($z, $x) >= 0;
			$is_ok = 0 unless $cmp->($y, $x) >= 0;
			$is_ok = 0 unless $cmp->($z, $y) >= 0;
	
			no warnings 'uninitialized';
			ok $is_ok, "comparsion function should be transitive with [$t1, $m1], [$t2, $m2], [$t3, $m3]";
		}
		{
			use sort 'stable';
			my @order3 = sort { $cmp->($a, $b) } ( $f1, $f2, $f3 );
			my @order2 = sort { $cmp->($a, $b) } ( $f1,      $f3 );
			
			my @order2a = grep { $_ != $f2 } @order3;
			
			no warnings 'uninitialized';
			ok $order2[0] == $order2a[0] && $order2[1] == $order2a[1], "adding element to array should not change relative order of other elements [$t1, $m1], [$t2, $m2], [$t3, $m3]";
		}
		{
			my @order1 = sort { $cmp->($a, $b) or $a <=> $b } ( $f1, $f2, $f3 ); # we add here another comparison function, to produce stable results
			my @order2 = sort { $cmp->($a, $b) or $a <=> $b } reverse ( $f1, $f2, $f3 );
			
			no warnings 'uninitialized';
			ok $order1[0] == $order2[0] && $order1[1] == $order2[1] && $order1[2] == $order2[2], "sort() and sort(reverse()) should return same data [$t1, $m1], [$t2, $m2], [$t3, $m3]";
		}
	}}
	}}
	}}
}


1;

