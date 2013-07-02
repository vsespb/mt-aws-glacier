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
use Test::More tests => 1;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::FileVersions;
use TestUtils;

warning_fatal();

my $cmp = \&App::MtAws::FileVersions::_cmp;

#
# Let's try to define function normalize(), so that
# normalize(a) <=> normalize(b) MUST equal to $cmp->(a, b);
# 
sub normalize
{
	my ($a) = @_;
	sprintf("%011d%011d", defined($a->{mtime}) ? ($a->{mtime}, $a->{time})  : ($a->{time}, $a->{time}));
}

#
# This test tests _cmp function behaviour (like transitivity), so you can change function algorithm, but this
# test must pass anyway (i.e. it passes for different function without changing test code)
#
# Except you need to edit normalize() function

sub object { { time => $_[0], mtime => $_[1] } }

test_fast_ok 5484, "file versions comparison function should behave right" => sub {
	my @all = (1,2,3);
	for my $t1 (@all) { for my $m1 (@all, undef) { 
	my $f1 = object($t1, $m1);
	
	#
	# work with all permutations of one object
	#
	
	# Testing Irreflexivity
	fast_ok $cmp->($f1, $f1) == 0;
	
	for my $t2 (@all) { for my $m2 (@all, undef) {
	my $f2 = object($t2, $m2);
	
	#
	# work with all permutations of two objects
	#
	{
		# Testing Antisymmetry
		fast_ok $cmp->($f1, $f2) * $cmp->($f2, $f1) <= 0;
		
		no warnings 'uninitialized';
		# Testing with normalize()
		fast_ok $cmp->($f1, $f2) == (normalize($f1) <=> normalize($f2)),
			sub { "normalize([$t1, $m1]) <=> normalize([$t2, $m2]) should be equal to cmp->([$t1, $m1], [$t2, $m2])" };
	}
	
	for my $t3 (@all) { for my $m3 (@all, undef) {
		my $f3 = object($t3, $m3);
		
		# work with all permutations of three objects
		
		{
			my $is_ok = 1;
			
			# Testing Transitivity of Equivalence
			if (($cmp->($f1, $f2) == 0) && ($cmp->($f2, $f3) == 0)) {
				$is_ok = 0 unless $cmp->($f1, $f3) == 0;
			}

			my ($x, $y, $z) = sort { $cmp->($a, $b) } ( $f1, $f2, $f3 );
			# transitivity
			$is_ok = 0 unless $cmp->($x, $z) <= 0;
			$is_ok = 0 unless $cmp->($x, $y) <= 0;
			$is_ok = 0 unless $cmp->($y, $z) <= 0;
	
			$is_ok = 0 unless $cmp->($z, $x) >= 0;
			$is_ok = 0 unless $cmp->($y, $x) >= 0;
			$is_ok = 0 unless $cmp->($z, $y) >= 0;
			
			no warnings 'uninitialized';
			fast_ok $is_ok, sub { "comparsion function should be transitive with [$t1, $m1], [$t2, $m2], [$t3, $m3]" };
		}
		{
			use sort 'stable';
			my @order3 = sort { $cmp->($a, $b) } ( $f1, $f2, $f3 );
			my @order2 = sort { $cmp->($a, $b) } ( $f1,      $f3 );
			
			my @order2a = grep { $_ != $f2 } @order3;
			
			no warnings 'uninitialized';
			fast_ok $order2[0] == $order2a[0] && $order2[1] == $order2a[1],
				sub { "adding element to array should not change relative order of other elements [$t1, $m1], [$t2, $m2], [$t3, $m3]" };
		}
		{
			my @order1 = sort { $cmp->($a, $b) or $a <=> $b } ( $f1, $f2, $f3 ); # we add here another comparison function, to produce stable results
			my @order2 = sort { $cmp->($a, $b) or $a <=> $b } reverse ( $f1, $f2, $f3 );
			
			no warnings 'uninitialized';
			fast_ok $order1[0] == $order2[0] && $order1[1] == $order2[1] && $order1[2] == $order2[2],
				sub { "sort() and sort(reverse()) should return same data [$t1, $m1], [$t2, $m2], [$t3, $m3]" };
		}
	}}
	}}
	}}
};


1;

