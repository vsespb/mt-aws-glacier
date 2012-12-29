#!/usr/bin/perl


use strict;
use warnings;
use utf8;
use Test::More tests => 11;
use lib qw{.. ../..};
use TreeHash;
use Data::Dumper;


#die TreeHash::maxpower(16);

{
	my $s = "Hello, world! ".('x' x 100);
	
	my $th = TreeHash->new(unit => 7);
	$th->eat_data(\$s);
	$th->calc_tree();
	
	my $th2 = TreeHash->new(unit => 7);
	$th2->eat_data($s);
	$th2->calc_tree();
	ok ( $th->get_final_hash() eq $th2->get_final_hash(), 'should work for both ref and non-ref' );
}

{
	my $s = "Hello, world! ".('x' x 100);
	
	my $th = TreeHash->new(unit => 7);
	$th->eat_data(\$s);
	$th->calc_tree();
	my $hash = $th->get_final_hash();
	ok ( $hash eq '4d3daa9c69c202566f83bebfce9de1751a306af96dbf3a69874800aa8b96ad6d', 'should work for data larger than unit size' );
}

{
	my $s = "Hello, world! ".('x' x 100);
	
	my $th = TreeHash->new(unit => 1048576);
	$th->eat_data(\$s);
	$th->calc_tree();
	my $hash = $th->get_final_hash();
	ok ( $hash eq '15aad04dbdebee9ad90ba889d8eb3b9045be355fed57c62894bc2b1ae259c8c8', 'should work for data smaller than unit size' );
}

{
	my $chunk = 128;
	my $s = "s" x $chunk;
	
	my $th = TreeHash->new(unit => $chunk);
	$th->_eat_data_one_mb(\$s);
	$th->calc_tree();
	
	my $th2 = TreeHash->new(unit => $chunk);
	$th2->_eat_data_one_mb($s);
	$th2->calc_tree();
	ok ( $th->get_final_hash() eq $th2->get_final_hash(), '_eat_data_one_mb should work for both ref and non-ref' );
}

{
	my $chunk = 128;
	my @data = map { sprintf("%s%011d", ('x' x ($chunk - 11)), $_) } 1..100;

	ok length( $data[0]) == $chunk, "assumtion that length is correct";
	
	my $th_simple = TreeHash->new(unit => $chunk);
	
	for (@data) {
		$th_simple->_eat_data_one_mb(\$_);
	}
	
	$th_simple->calc_tree();
	my $simplehash = $th_simple->get_final_hash();
	
	my $th_complex = TreeHash->new(unit => $chunk);
	$th_complex->eat_data(join('', @data));
	$th_complex->calc_tree();

	ok($th_complex->get_final_hash() eq $simplehash, "eat_another_treehash should work");
}



{
	my $chunk = 128;
	my @data = map { sprintf("%s%011d", ('x' x ($chunk - 11)), $_) } 1..100;

	ok length( $data[0]) == $chunk, "assumtion that length is correct";
	
	my $th_simple = TreeHash->new(unit => $chunk);
	
	for (@data) {
		$th_simple->_eat_data_one_mb(\$_);
	}
	
	$th_simple->calc_tree();
	my $simplehash = $th_simple->get_final_hash();

	my $th_complex = TreeHash->new(unit => $chunk);
	for (@data) {
		my $th_chunk = TreeHash->new(unit => $chunk);
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
	
	my $th_simple = TreeHash->new(unit => $chunk);
	
	for (@data) {
		$th_simple->_eat_data_one_mb(\$_);
	}
	
	$th_simple->calc_tree();
	my $simplehash = $th_simple->get_final_hash();

	my $th_complex = TreeHash->new(unit => $chunk);
	for (@data) {
		my $th_chunk = TreeHash->new(unit => $chunk);
		$th_chunk->_eat_data_one_mb(\$_);
		$th_chunk->calc_tree();
		$th_complex->eat_another_treehash($th_chunk);
	}
	$th_complex->calc_tree();

	ok($th_complex->get_final_hash() eq $simplehash, "eat_another_treehash should work even if tree calculated");
}

{
	my $chunk = 128;
	my $th_simple = TreeHash->new(unit => $chunk);
	eval {
		$th_simple->_eat_data_one_mb('x' x ($chunk-1));
		$th_simple->_eat_data_one_mb('x' x $chunk);
		$th_simple->calc_tree();
	};
	ok ($@ ne '', "Should warn that previous chunk of data was less than 1MiB");
}

1;
