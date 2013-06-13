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
use Test::More tests => 617;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::FileVersions;
use TestUtils;

warning_fatal();

sub object
{
	my ($time, $mtime, $filename, $archive_id) = @_;
	{ time => $time, mtime => $mtime, ($filename ? (filename => $filename) : () ), ($archive_id ? (archive_id => $archive_id) : () )}; 
}

# _cmp tests

{
	my $cmp = \&App::MtAws::FileVersions::_cmp;
	
	for ([undef, undef], [777, 777], [undef, 100], [100, undef]) {
		is $cmp->(object(123, $_->[0]), object(456, $_->[1])), -1, "cmp should work when mtime is undef or equal and a.time < b.time";
		is $cmp->(object(456, $_->[0]), object(123, $_->[1])), 1, "cmp should work when mtime is undef or equal and a.time > b.time";
		is $cmp->(object(456, $_->[0]), object(456, $_->[1])), 0, "cmp should work when mtime is undef or equal and a.time == b.time";
	}
	
	for ([42, 43], [43, 42]) {
		is $cmp->(object($_->[0], 123), object($_->[1], 456)), -1, "cmp should work when a.mtime < b.mtime";
		is $cmp->(object($_->[0], 456), object($_->[1], 123)), 1, "cmp should work when a.mtime > b.mtime";
	}
}

# _mid tests

{
	my $mid = \&App::MtAws::FileVersions::_mid;
	for my $base (0..3) {
		is $mid->($base, $base+0), $base+0;
		is $mid->($base, $base+1), $base+0;
		is $mid->($base, $base+2), $base+1;
		is $mid->($base, $base+3), $base+1;
		is $mid->($base, $base+4), $base+2;
		is $mid->($base, $base+5), $base+2;
	}
}

# _find tests

{
	my $v = bless [], 'App::MtAws::FileVersions';
	ok ! defined $v->_find(object(5)), '_find 0 elements, should return before everything';
}

{
	my $v = bless [object(10)], 'App::MtAws::FileVersions';
	ok ! defined $v->_find(object(5)), '_find 1 element, should return before everything';
	is $v->_find(object(15)), 0, '_find 1 element, should return after 0-th';
	is $v->_find(object(10)), 0, '_find 1 element, should return after 0-th if elements are equal';
}

{
	my $v = bless [object(10), object(20)], 'App::MtAws::FileVersions';
	ok ! defined $v->_find(object(5)), '_find 2 element, should return before everything';
	is $v->_find(object(10)), 0, '_find 2 element, should return after 0-th if elements are equal';
	is $v->_find(object(15)), 0, '_find 2 element, should return after 0-th';

	is $v->_find(object(20)), 1, '_find 2 element, should return after 1st if elements are equal';
	is $v->_find(object(25)), 1, '_find 2 element, should return after 1st';
}

# same tests as above, but for N elements
for (1..10) {
	my @elements = map { $_* 10 } 1..$_;
	my $v = bless [map { object($_) } @elements], 'App::MtAws::FileVersions';
	
	for (my $i = 0; $i <= $#elements; ++$i) {
		is $v->_find(object($elements[$i])), $i, "find $_ elements, should return after $i";
		if ($i > 0) {
			is $v->_find(object($elements[$i]-3)), $i - 1, "find $_ elements, should return after ".($i-1)." for ".($elements[$i]-3);
		} else {
			ok ! defined $v->_find(object($elements[$i]-3)), "find $_ elements, should return before everything for ".($elements[$i]-3);
		}
		if ($i == $#elements) {
			is $v->_find(object($elements[$i]+3)), $i, "find $_ elements, should return after ".($i)." for ".($elements[$i]+3);
		}
	}
}

# same "stresstest", but some elements have repeations
{
	for my $before (1..6) { for my $same (1..6) { for my $after (1..6) {
		my @elements = ( (map { $_* 10 } 1..$before), (map { ($before + 1) * 10 } 1..$same), (map { ($before + 1) * 10 + $_* 10 } 1..$after) );
		my $v = bless [map { object($_) } @elements], 'App::MtAws::FileVersions';
		my $ok = 1;
		my %seen;
		for (my $i = 0; $i <= $#elements; ++$i) {
			next if $seen{$elements[$i]}++; # we have some repetions (array produced with $same)
			my $after = $v->_find(object($elements[$i]));
			$ok &&= $elements[$after] <= $elements[$i];
			if ($after+1 <= $#elements) {
				$ok &&= $elements[$after+1] > $elements[$i];
			}
			my $after2 = $v->_find(object($elements[$i]-3));
			if (defined $after2) {
				$ok &&= $elements[$after2] <= $elements[$i]-3;
				if ($after2+1 <= $#elements) {
					$ok &&= $elements[$after2+1] > $elements[$i]-3;
				}
			} else {
				$ok &&= $elements[0] > $elements[$i]-3;
			}
		}
		ok $ok;
	}}}
}

# adding elements tests

for (100, 123, 300) {
	my $v = App::MtAws::FileVersions->new();
	my $o1 = object(123);
	my $o2 = object($_, undef, 'latest');
	$v->add($o1);
	$v->add($o2);
	is scalar @$v, 2, "should add second element";
	ok $v->[0]{time} <= $v->[1]{time}, "should add second element right";
	if ($v->[0]{time} == $v->[1]{time}) {
		ok !$v->[0]{filename} && $v->[1]{filename} eq 'latest', "if everything equal, later added element should go last"
	}
}

for (100, 300, 500) {
	my $v = App::MtAws::FileVersions->new();
	my $o1 = object(123);
	my $o2 = object(456);
	my $o3 = object($_);
	$v->add($o1);
	$v->add($o2);
	$v->add($o3);
	is scalar @$v, 3, "should add third element";
	ok $v->[0]{time} < $v->[1]{time}, "should add third element right";
	ok $v->[1]{time} < $v->[2]{time}, "should add third element right";
}

for (100, 200, 201, 211, 300, 310, 311, 321, 330, 500) {
	my $v = App::MtAws::FileVersions->new();
	my @objects;
	for my $el ((200, 210, 220, 230, 310, 320, 330)) {
		my $o = object($el);
		push @objects, $o;
		$v->add($o);
	}
	my $o = object($_, undef, 'latest');
	$v->add($o);
	push @objects, $o;
	is scalar @$v, 8, "should add $_";
	is scalar $v->all, scalar @$v, "all() should return all data";
	cmp_deeply [$v->all], [sort { App::MtAws::FileVersions::_cmp($a, $b) } @objects], "all should return sorted data";
	for (my $i = 0; $i < $#$v; ++$i) {
		ok $v->[$i]{time} <= $v->[$i+1]{time}, "$i-th element ($v->[$i]{time}) should be less then next one ($v->[$i+1]{time}), for $_";
		if ($v->[$i]{time} == $v->[$i+1]{time}) {
			ok !$v->[$i]{filename} && $v->[$i+1]{filename} eq 'latest', "if everything equal, later added element should go last"
		}
	}
}

# _delete_by_archive_id test
{
	my $v = App::MtAws::FileVersions->new();
	my $aid = 'abc123';
	$v->add(object(123, undef, undef, $aid));
	is scalar @$v, 1, "should contain one element";
	ok $v->delete_by_archive_id($aid);
	is scalar @$v, 0, "deletion of one element should work";
}

{
	sub create_objects
	{
		my ($v, $n) = @_;
		my @filenames;
		for my $i (1..$_-2) {
			$v->add(object(200+$i, undef, "a$i", "id$i"));
			push @filenames, "a$i";
		}
		@filenames;
	}
	for (2..10) {
		{
			my $v = App::MtAws::FileVersions->new();
			my $aid = 'abc123';
			$v->add(object(123, undef, 'f1', 'anotherid'));
			$v->add(object(456, undef, 'f2', $aid));
			
			my @filenames = create_objects($v, $_-2);
			
			is scalar @$v, $_, "should contain $_ elements";
			cmp_deeply [map { $_->{filename} } @$v], ['f1', @filenames, 'f2'];
			ok $v->delete_by_archive_id($aid);
			is scalar @$v, $_ - 1, "deletion of last element should work in $_-items array";
			cmp_deeply [map { $_->{filename} } @$v], ['f1', @filenames];
			ok !$v->delete_by_archive_id('nonexistant');
		}
		{
			my $v = App::MtAws::FileVersions->new();
			my $aid = 'abc123';
			$v->add(object(123, undef, 'f1', $aid));
			$v->add(object(456, undef, 'f2', 'anotherid'));
			
			my @filenames = create_objects($v, $_-2);
			
			is scalar @$v, $_, "should contain $_ elements";
			cmp_deeply [map { $_->{filename} } @$v], ['f1', @filenames, 'f2'];
			ok $v->delete_by_archive_id($aid);
			is scalar @$v, $_ - 1, "deletion of first element should work in $_-items array";
			cmp_deeply [map { $_->{filename} } @$v], [@filenames, 'f2'];
			ok !$v->delete_by_archive_id('nonexistant');
		}
	}
}

# these tests does not make sense, as sort behaviour already tested above
# but I still implement this to define how files can be sorted in practice
{
	my $v = App::MtAws::FileVersions->new();
	$v->add(object(7, undef, 'f1'));
	$v->add(object(8, 5, 'f2')); # loaded later than f1, but we know mtime of f2 is before f1 is loaded
	# anyway we ignore mtime and think who is later loaded is older
	
	cmp_deeply [map { $_->{filename} } @$v], [qw/f1 f2/], "objects without mtime can be on top"
	
}

{
	my $v = App::MtAws::FileVersions->new();
	$v->add(object(7, undef, 'f1'));
	$v->add(object(7, 5, 'f2'));
	
	cmp_deeply [map { $_->{filename} } @$v], [qw/f1 f2/], "if at least one mtime missed, and time is same, we go natural order"
}
1;

