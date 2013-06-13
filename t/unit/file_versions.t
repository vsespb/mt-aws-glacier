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
use Test::More tests => 116;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::FileVersions;
use TestUtils;

warning_fatal();

sub object
{
	my ($time, $mtime, $filename) = @_;
	{ time => $time, mtime => $mtime, ($filename ? (filename => $filename) : () )}; 
}

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

for (100, 123, 300) {
	my $v = App::MtAws::FileVersions->new();
	my $o1 = object(123, undef);
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
	my $o1 = object(123, undef);
	my $o2 = object(456, undef);
	my $o3 = object($_, undef);
	$v->add($o1);
	$v->add($o2);
	$v->add($o3);
	is scalar @$v, 3, "should add third element";
	ok $v->[0]{time} < $v->[1]{time}, "should add third element right";
	ok $v->[1]{time} < $v->[2]{time}, "should add third element right";
}

for (100, 200, 201, 211, 300, 310, 311, 321, 330, 500) {
	my $v = App::MtAws::FileVersions->new();
	for my $el (200, 210, 220, 230, 310, 320, 330) {
		$v->add(object($el, undef));
	}
	$v->add(object($_, undef, 'latest'));
	is scalar @$v, 8, "should add $_";
	for (my $i = 0; $i < $#$v; ++$i) {
		ok $v->[$i]{time} <= $v->[$i+1]{time}, "$i-th element ($v->[$i]{time}) should be less then next one ($v->[$i+1]{time}), for $_";
		if ($v->[$i]{time} == $v->[$i+1]{time}) {
			ok !$v->[$i]{filename} && $v->[$i+1]{filename} eq 'latest', "if everything equal, later added element should go last"
		}
	}
}

# these tests does not make sense, as sort behaviour already tested above
# but I still implement this to define how files can be sorted in practice
{
	my $v = App::MtAws::FileVersions->new();
	$v->add(object(3, 123, 'f1'));
	$v->add(object(4, undef, 'withoutname'));
	$v->add(object(2, 456, 'f2'));
	
	cmp_deeply [map { $_->{filename} } @$v], [qw/f1 f2 withoutname/], "objects without mtime can be on top"
	
}

1;

