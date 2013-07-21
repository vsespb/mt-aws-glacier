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
use Test::More tests => 1417;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::TreeHash;
use Data::Dumper;

local $SIG{__WARN__} = sub {die "Termination after a warning: $_[0]"};

# eat_data_any_size

sub test_eat_data_any_size
{
	my $unit = shift;
	my $th = App::MtAws::TreeHash->new(unit => $unit);
	my $s = '';
	my $original = join(',', @_);
	for (@_) {
		$s .= $_;
		$th->eat_data_any_size($_);
	}
	my $after_work = join(',', @_);
	is $after_work, $original, 'ensure source data is not modified';
	$th->calc_tree();
	# TODO: can mock eat_data_one_mb and collect and compare data instead of calculating treehash..
	my $th2 = App::MtAws::TreeHash->new(unit => $unit);
	$th2->eat_data($s);
	$th2->calc_tree();
	ok ( $th->get_final_hash() eq $th2->get_final_hash(), 'eat_data_any_size should work for '.join(',', @_) );
}

{
	my $chunksize = 3;
	my $maxstrsize = $chunksize + 1 + 1;
	my $bigstring = 'ABCDEFGHIJKLMNOPQRST';
	is length($bigstring),  $maxstrsize*4;
	for my $a1 (1..$maxstrsize) {
		my $s1 = substr('12345', 0, $a1); # TODO: test, that each string should consists of unique characters only
		is length($s1), $a1;
		for my $a2 (1..$maxstrsize) {
			my $s2 = substr('67890', 0, $a2);
			is length($s2), $a2;
			for my $a3 (1..$maxstrsize) {
				my $s3 = substr('abcde', 0, $a3);
				is length($s3), $a3;
				test_eat_data_any_size $chunksize, $s1, $s2, $s3;
				test_eat_data_any_size $chunksize, $bigstring, $s1, $s2, $s3;
				test_eat_data_any_size $chunksize, $s1, $bigstring, $s2, $s3;
				test_eat_data_any_size $chunksize, $s1, $s2, $bigstring, $s3;
				test_eat_data_any_size $chunksize, $s1, $s2, $s3, $bigstring;
			}
		}
	}
}


{
	my $s = "Hello, world! ".('x' x 100);
	
	my $th = App::MtAws::TreeHash->new(unit => 7);
	$th->eat_data(\$s);
	$th->calc_tree();
	my $th2 = App::MtAws::TreeHash->new(unit => 7);
	$th2->eat_data($s);
	$th2->calc_tree();
	ok ( $th->get_final_hash() eq $th2->get_final_hash(), 'should work for both ref and non-ref' );
}

{
	my $s = "Hello, world! ".('x' x 100);
	
	my $th = App::MtAws::TreeHash->new(unit => 7);
	$th->eat_data(\$s);
	$th->calc_tree();
	my $hash = $th->get_final_hash();
	ok ( $hash eq '4d3daa9c69c202566f83bebfce9de1751a306af96dbf3a69874800aa8b96ad6d', 'should work for data larger than unit size' );
}

{
	my $s = "Hello, world! ".('x' x 100);
	
	my $th = App::MtAws::TreeHash->new(unit => 1048576);
	$th->eat_data(\$s);
	$th->calc_tree();
	my $hash = $th->get_final_hash();
	ok ( $hash eq '15aad04dbdebee9ad90ba889d8eb3b9045be355fed57c62894bc2b1ae259c8c8', 'should work for data smaller than unit size' );
}

{
	my $chunk = 128;
	my $s = "s" x $chunk;
	
	my $th = App::MtAws::TreeHash->new(unit => $chunk);
	$th->_eat_data_one_mb(\$s);
	$th->calc_tree();
	
	my $th2 = App::MtAws::TreeHash->new(unit => $chunk);
	$th2->_eat_data_one_mb($s);
	$th2->calc_tree();
	ok ( $th->get_final_hash() eq $th2->get_final_hash(), '_eat_data_one_mb should work for both ref and non-ref' );
}

{
	my $chunk = 128;
	my @data = map { sprintf("%s%011d", ('x' x ($chunk - 11)), $_) } 1..100;

	ok length( $data[0]) == $chunk, "assumtion that length is correct";
	
	my $th_simple = App::MtAws::TreeHash->new(unit => $chunk);
	
	for (@data) {
		$th_simple->_eat_data_one_mb(\$_);
	}
	
	$th_simple->calc_tree();
	my $simplehash = $th_simple->get_final_hash();
	
	my $th_complex = App::MtAws::TreeHash->new(unit => $chunk);
	$th_complex->eat_data(join('', @data));
	$th_complex->calc_tree();

	ok($th_complex->get_final_hash() eq $simplehash, "eat_data should work");
}



{
	my $chunk = 128;
	my @data = map { sprintf("%s%011d", ('x' x ($chunk - 11)), $_) } 1..100;

	ok length( $data[0]) == $chunk, "assumtion that length is correct";
	
	my $th_simple = App::MtAws::TreeHash->new(unit => $chunk);
	
	for (@data) {
		$th_simple->_eat_data_one_mb(\$_);
	}
	
	$th_simple->calc_tree();
	my $simplehash = $th_simple->get_final_hash();

	my $th_complex = App::MtAws::TreeHash->new(unit => $chunk);
	for (@data) {
		my $th_chunk = App::MtAws::TreeHash->new(unit => $chunk);
		$th_chunk->_eat_data_one_mb(\$_);
		$th_complex->eat_another_treehash($th_chunk);
	}
	$th_complex->calc_tree();

	ok($th_complex->get_final_hash() eq $simplehash, "eat_another_treehash should work");
}

{
	my $chunk = 128;
	my @data = map { sprintf("%s%011d", ('x' x ($chunk - 11)), $_) } 1..100;

	ok length( $data[0]) == $chunk, "assumtion that length is correct";
	
	my $th_simple = App::MtAws::TreeHash->new(unit => $chunk);
	
	for (@data) {
		$th_simple->_eat_data_one_mb(\$_);
	}
	
	$th_simple->calc_tree();
	my $simplehash = $th_simple->get_final_hash();

	my $th_complex = App::MtAws::TreeHash->new(unit => $chunk);
	for (@data) {
		my $th_chunk = App::MtAws::TreeHash->new(unit => $chunk);
		$th_chunk->_eat_data_one_mb(\$_);
		$th_chunk->calc_tree();
		$th_complex->eat_another_treehash($th_chunk);
	}
	$th_complex->calc_tree();

	ok($th_complex->get_final_hash() eq $simplehash, "eat_another_treehash should work even if tree calculated");
}

{
	my $chunk = 128;
	my $th_simple = App::MtAws::TreeHash->new(unit => $chunk);
	eval {
		$th_simple->_eat_data_one_mb('x' x ($chunk-1));
		$th_simple->_eat_data_one_mb('x' x $chunk);
		$th_simple->calc_tree();
	};
	ok ($@ ne '', "Should warn that previous chunk of data was less than 1MiB");
}

sub maxpower_test
{
	my ($x) = @_;
	die if $x == 0;
	for (0..31) {
		my $n = 2**$_;
		return 2**($_-1)  if ($n >= $x);
	}
}

1;
