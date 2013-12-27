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


use strict;
use warnings;
use utf8;
use Test::More tests => 231;
use Test::Deep;
use Carp;
use Encode;
use FindBin;
use POSIX;
use lib map { "$FindBin::RealBin/$_" } qw{../../lib ../../../lib};
use Data::Dumper;

use App::MtAws::RdWr::Read;
use App::MtAws::RdWr::Readahead;
use TestUtils;


my $mtroot = get_temp_dir();
open(my $tmp, ">", "$mtroot/infile") or confess;
close $tmp;
open(my $in, "<", "$mtroot/infile") or confess;

warning_fatal();

{
	no warnings 'redefine';

	our @queue;
	local $!;
	local *App::MtAws::RdWr::Read::_sysread = sub {
		confess unless @queue;
		my $pos = $_[3]||0;
		$_[1] = '' unless defined $_[1];
		my $q = shift @queue;
		my $expected_size = shift @queue;
		confess $expected_size unless $expected_size;
		confess "$expected_size == $_[2]" unless $expected_size == $_[2];
		$! = 0;
		return 0 if $q eq 'EOF';
		return undef if $q eq 'ERR';
		if ($q eq 'EINTR') {
			$! = EINTR;
			return undef;
		}
		confess "q [$q] greated than expected_size $expected_size" if length($q) > $expected_size;
		my $len = length( $_[1] );
		$_[1] .= "0" x ( $pos - $len ) if $len < $pos; # original sysread uses 0x00

		substr($_[1], $pos) = $q;
		length $q;
	};

	# test the test - how our test code _sysread works
	{
		local @queue;
		ok ! defined eval { App::MtAws::RdWr::Read::_sysread($in, my $x, 1); 1 };
	}
	{
		local @queue = (EOF => 1);
		is App::MtAws::RdWr::Read::_sysread($in, my $x, 1), 0;
		is $x, '';
		ok !$!;
	}
	{
		local @queue = (ERR => 2);
		is App::MtAws::RdWr::Read::_sysread($in, my $x, 2), undef;
		is $x, '';
		ok !$!;
	}
	{
		local @queue = (EINTR => 3);
		is App::MtAws::RdWr::Read::_sysread($in, my $x, 3), undef;
		is $x, '';
		ok $!{EINTR};
	}
	{
		local @queue = (a => 1);
		is App::MtAws::RdWr::Read::_sysread($in, my $x, 1), 1;
		is $x, 'a';
		ok !$!;
	}
	{
		local @queue = (a => 1);
		is App::MtAws::RdWr::Read::_sysread($in, my $x, 1, 1), 1;
		is $x, '0a';
		ok !$!;
	}
	{
		local @queue = (d => 1);
		my $x = 'abc';
		is App::MtAws::RdWr::Read::_sysread($in, $x, 1, 3), 1;
		is $x, 'abcd';
		ok !$!;
	}

	sub rd
	{
		App::MtAws::RdWr::Read->new($in);
	}

	sub readahead
	{
		App::MtAws::RdWr::Readahead->new($in);
	}


	# actual test
	{
		local @queue = (ab => 2);
		is rd->sysreadfull(my $x, 2), 2;
		is $x, 'ab', "should work in simple case";
	}

	{
		local @queue = (a => 3, bc => 2);
		is rd->sysreadfull(my $x, 3), 3;
		is $x, 'abc', "should work with two reads";
	}
	{
		local @queue = (ab => 5, c => 3, de => 2);
		is rd->sysreadfull(my $x, 5), 5;
		is $x, 'abcde', "should work with three reads";
	}
	{
		local @queue = (ab => 5, c => 3, de => 2);
		is rd->sysreadfull(my $x, 5), 5;
		is $x, 'abcde', "should work with three reads";
	}
	{
		local @queue = (ab => 5, c => 3, EOF => 2);
		is rd->sysreadfull(my $x, 5), 3;
		is $x, 'abc', "should work when eof not reached";
	}
	{
		local @queue = (EOF => 5);
		is rd->sysreadfull(my $x, 5), 0;
		is $x, '', "should work with eof in the beginning";
	}
	{
		local @queue = (ERR => 5);
		is rd->sysreadfull(my $x, 5), undef;
		is $x, '', "should work with ERROR in the beginning";
	}
	{
		local @queue = (ab => 5, c => 3, ERR => 2, ERR => 7);
		my $rd = rd;
		is $rd->sysreadfull(my $x, 5), 3;
		is $x, 'abc', "should work with ERROR in the middle";
		is $rd->sysreadfull(my $y, 7), undef;
	}
	{
		local @queue = (ab => 5, c => 3, EINTR => 2, de => 2);
		is rd->sysreadfull(my $x, 5), 5;
		is $x, 'abcde', "should work with EINTR in the middle";
	}
	{
		local @queue = (ab => 5, c => 3, EINTR => 2, d => 2, EOF => 1);
		is rd->sysreadfull(my $x, 5), 4;
		is $x, 'abcd', "should work with EINTR in the middle, when there will be eof";
	}
	{
		local @queue = (ab => 5, c => 3, EINTR => 2, d => 2, ERR => 1);
		is rd->sysreadfull(my $x, 5), 4;
		is $x, 'abcd', "should work with EINTR in the middle, when there will be ERROR";
	}
	{
		local @queue = (EINTR => 5, ab => 5, c => 3, EINTR => 2, EINTR => 2, d => 2, EINTR => 1, ERR => 1);
		is rd->sysreadfull(my $x, 5), 4;
		is $x, 'abcd', "should work with several EINTR";
	}
	{
		local @queue = (ab => 5, EINTR => 3, EINTR => 3, c => 3, d => 2, EINTR => 1, EOF => 1);
		is rd->sysreadfull(my $x, 5), 4;
		is $x, 'abcd', "should work with several EINTR";
	}


	sub gen_string
	{
		my ($n, $pre_readaheads) = (@_, 0);
		join('', map { chr(ord('a')+$_+$pre_readaheads-1) } 1..$n)
	}

	for my $pre_readaheads (0..4) {#3
		for my $n ($pre_readaheads+1..5) {
			for my $k (1..5) {
				my $str_n = gen_string($n);
				my $str_k = gen_string($k);
				local @queue;

				my $rd = readahead;
				for my $i (1..$pre_readaheads) {
					push @queue, (chr(ord('a')+$i-1) => 1);#, EOF => $k-$n
					$rd->readahead(1);
				}
				push @queue,
					(gen_string($n-$pre_readaheads, $pre_readaheads) =>
					 $n-$pre_readaheads, EOF => $k-$n ? $k-$n : 1); # 1 is for eof tes
				$rd->readahead($n-$pre_readaheads);

				my $res = $rd->read(my $x, $k);
				if ($k >= $n) {
					is $x, $str_n, "$pre_readaheads prereadaheads. read for higher or same data size $k >= $n";
					is $res, $n;
					ok !$rd->read($x, 1);
				} else {
					is $x, $str_k, "$pre_readaheads prereadaheads. read for smaller data size $k < $n";
					is $res, $k;
				}
			}
		}
	}
}


1;
__END__
