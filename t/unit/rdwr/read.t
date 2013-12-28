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
use Test::More tests => 124;
use Test::Deep;
use Carp;
use Encode;
use FindBin;
use POSIX;
use lib map { "$FindBin::RealBin/$_" } qw{../../lib ../../../lib};
use List::Util qw/max/;
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
		confess if $expected_size < 0;
		confess "[$q] $expected_size" unless $expected_size;
		confess "[$q] $expected_size == $_[2]" unless $expected_size == $_[2];
		$! = 0;
		return 0 if $q eq 'EOF';
		return undef if $q eq 'ERR';
		if ($q eq 'EINTR') {
			$! = EINTR;
			return undef;
		}
		confess "q [$q] greated than expected_size $expected_size" if length($q) > $expected_size;
		my $len = length( $_[1] );
		$_[1] .= "\x00" x ( $pos - $len ) if $len < $pos; # original sysread uses 0x00

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
		is $x, "\x00a";
		ok !$!;
	}
	{
		local @queue = (d => 1);
		my $x = 'abc';
		is App::MtAws::RdWr::Read::_sysread($in, $x, 1, 3), 1;
		is $x, 'abcd';
		ok !$!;
	}

	sub rd { die "Unimplemented" }
	sub get_rd { App::MtAws::RdWr::Read->new($in) }
	sub get_readahead { App::MtAws::RdWr::Readahead->new($in) }

	for my $factory(\&get_rd, \&get_readahead) {

		local *rd = $factory;

		# actual test sysreadfull
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

		# actual test read()
		{
			local @queue = (ab => 5, EOF => 3);
			my $rd = rd;
			is $rd->read(my $x, 5), 2;
			is $x, "ab";
			is $rd->read(my $y, 5), 0;
			is $y, '', "read() should not try read after eof again. should initialize value to empty string";
		}

		{
			local @queue = (EOF => 5);
			my $rd = rd;
			is $rd->read(my $x, 5), 0;
			is $x, '', 'read() should initialize value to empty string if eof found';
			is $rd->read(my $y, 5), 0;
			is $y, '', "read() should not try read after eof again. even if eof is the first thing found in steam";
		}

		{
			local @queue = (ab => 5, ERR => 3);
			my $rd = rd;
			is $rd->read(my $x, 5), 2;
			is $x, "ab";
			ok ! defined $rd->read(my $y, 5);
			is $y, '', "read() should not try read after error again. should initialize value to empty string";
		}

		{
			local @queue = (ERR => 5);
			my $rd = rd;
			ok ! defined $rd->read(my $x, 5);
			is $x, '', 'read() should initialize value to empty string if error found';
			ok ! defined $rd->read(my $y, 5);
			is $y, '', "read() should not try read after error again. even if error is the first thing found in steam";
		}

		{
			local @queue = (ab => 5, EOF => 3);
			my $rd = rd;
			is $rd->read(my $x, 5, 1), 2;
			is $x, "\x00ab";
		}
		{
			local @queue = (ab => 5, EOF => 3);
			my $rd = rd;
			is $rd->read(my $x, 5, 2), 2;
			is $x, "\x00\x00ab";
		}
		{
			local @queue = (EOF => 5);
			my $rd = rd;
			is $rd->read(my $x, 5, 2), 0;
			is $x, "\x00\x00";
		}
	}

	# unit tests for readahead

	{
		local @queue = (ab => 5, EOF => 3);
		my $rd = get_readahead;
		is $rd->readahead(5), 2;
		is $rd->read(my $x, 5, 2), 2;
		is $x, "\x00\x00ab";
	}
	{
		local @queue = (EOF => 5);
		my $rd = get_readahead;
		is $rd->readahead(5), 0;
		is $rd->read(my $x, 5, 2), 0;
		is $x, "\x00\x00";
	}

	sub gen_string
	{
		my ($n, $pre_readaheads) = (@_, 0);
		join('', map { chr(ord('a')+$_+$pre_readaheads-1) } 1..$n)
	}

	# I already dont understand how this test works.
	# it's integration test. if it broke - take a debugger, investigate and fix.
	test_fast_ok 1152, "integration test for readahead" => sub {
	for my $init_offset (0, 1) {
		for my $pre_readaheads (0..4) {
			for my $n (max($pre_readaheads, 1)..5) {
				for my $k (1..5) {
					for my $read_ahead_meets_eof ($k > $n ? (0, 1) : 0) {
						my $str_n = gen_string($n);
						my $str_k = gen_string($k);
						local @queue;

						my $rd = get_readahead;
						for my $i (1..$pre_readaheads) {
							push @queue, (chr(ord('a')+$i-1) => 1);#, EOF => $k-$n
							$rd->readahead(1);
						}
						my $n_but_pre_readaheads = $n-$pre_readaheads;
						push @queue,
							($n_but_pre_readaheads ? (gen_string($n_but_pre_readaheads, $pre_readaheads) => $n_but_pre_readaheads) : ()),
							(EOF => $k-$n > 0 ? $k-$n : 1);
						fast_ok $rd->readahead($n_but_pre_readaheads) == $n_but_pre_readaheads;

						fast_ok $rd->readahead($k-$n) == 0 if $read_ahead_meets_eof;

						my ($x, $pre);
						if ($init_offset) {
							$pre = '1';
							$x = $pre;
						} else {
							$pre = '';
						}
						my $res = $rd->read($x, $k, $init_offset);
						if ($k >= $n) {
							fast_ok $x eq $pre.$str_n, sub { "$pre_readaheads prereadaheads. read for higher or same data size $k >= $n" };
							fast_ok $res == $n;
							fast_ok !$rd->read($x, 1);
						} else {
							fast_ok $x eq $pre.$str_k, sub { "$pre_readaheads prereadaheads. read for smaller data size $k < $n" };
							fast_ok $res == $k;
							my $z;
							$rd->read($z, $n-$k);
							fast_ok $x.$z eq $pre.$str_n;
							my $w;
							fast_ok !$rd->read($w, 1);
						}
					}
				}
			}
		}
	}
	}
}


1;
__END__
