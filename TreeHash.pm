# mt-aws-glacier - AWS Glacier sync client
# Copyright (C) 2012  Victor Efimov
# vs@vs-dev.com http://vs-dev.com
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


# 1) eat_data() for data
# 2) eat_1mb for data
# 3) define_hash
#


# treehash() = treehash(1,7) = sha ( treehash(1,4), teehash(5,7))
# treehash(1,4) = treehash(1,2).treehash(3,4)
# treehash(1,
#


package TreeHash;



use strict;
use warnings;
use Digest::SHA qw/sha256/;
use Carp;



sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    $self->{tree} = [];
    $self->{pending} = {};
    $self->{unit} ||= 1048576;
    $self->{processed_size} = 0; # MB
    bless $self, $class;
    return $self;
}


sub eat_file
{
	my ($self, $fh) = @_;
	while (1) {
		my $r = sysread($fh, my $data, $self->{unit});
		if (!defined($r)) {
			die;
		} elsif ($r > 0) {
			$self->_eat_data_one_mb(\$data);
		} else {
			return;
		}
	}
}

sub eat_data
{
	my $self = $_[0];
	my $dataref = (ref($_[1]) eq '') ? \$_[1] : $_[1];
	my $mb = $self->{unit};
	my $n = length($$dataref);
	# TODO: we should preserve last chunk of data actually, if it's smaller that chunk. (or create new method)
	if ($n <= $mb) {
		$self->_eat_data_one_mb($dataref);
	} else {
		my $i = 0;
		while ($i < $n) {
			my $part = substr($$dataref, $i, $mb);
			$self->_eat_data_one_mb(\$part);
			$i += $mb
		}
	}
}

sub eat_another_treehash
{
	my ($self, $th) = @_;
	croak unless $th->isa("TreeHash");
	$self->{tree}->[0] ||= [];
	my $cnt = scalar @{ $self->{tree}->[0] };
	my $newstart = $cnt ? $self->{tree}->[0]->[$cnt - 1]->{finish} + 1 : 0;
	
	push @{$self->{tree}->[0]}, map {
		$newstart++;
		{ joined => 9, start => $newstart-1, finish => $newstart-1, hash => $_->{hash} };
	} @{$th->{tree}->[0]};
}


sub _eat_data_one_mb
{
	my $self = $_[0];
	my $dataref = (ref($_[1]) eq '') ? \$_[1] : $_[1];
	$self->{tree}->[0] ||= [];
	
	if ($self->{last_chunk}) {
		croak "Previous chunk of data was less than 1MiB";
	}
	if (length($$dataref) > $self->{unit}) {
		croak "data chunk exceed 1MiB".length($$dataref);
	} elsif (length($$dataref) < $self->{unit}) {
		$self->{last_chunk} = 1;
	}
	
	push @{ $self->{tree}->[0] }, { joined => 0, start => $self->{processed_size}, finish => $self->{processed_size}, hash => sha256($$dataref) };
	$self->{processed_size}++;
}

sub calc_tree
{
	my ($self)  = @_;
	my $prev_level = 0;
	while (scalar @{ $self->{tree}->[$prev_level] } > 1) {
		my $curr_level = $prev_level+1;
		$self->{tree}->[$curr_level] = [];
		
		my $prev_tree = $self->{tree}->[$prev_level];
		my $curr_tree = $self->{tree}->[$curr_level];
		my $len = scalar @$prev_tree;
		for (my $i = 0; $i < $len; $i += 2) {
			if ($len - $i > 1) {
				my $a = $prev_tree->[$i];
				my $b = $prev_tree->[$i+1];
				push @$curr_tree, { joined => 0, start => $a->{start}, finish => $b->{finish}, hash => sha256( $a->{hash}.$b->{hash} ) };
			} else {
				push @$curr_tree, $prev_tree->[$i];
			}
		}
		
		$prev_level = $curr_level;
	}
}

# 
#
#

sub _treehash
{
	my ($self, $a, $b) = @_;
	if (defined($a)) {
		print "get $a,$b\t";
		if ($a == $b) {
			print "ok\n";
			return $self->_find($a);
		} else {
				my $mp = maxpower($b-$a+1);
				my $middle1 = $mp+$a-1;
				my $middle2 = $middle1 + 1 ;
				print "call ($a,$middle1) ($middle2,$b) -- $mp\n";
				return sha256 ($self->_treehash($a, $middle1 ).$self->_treehash($middle2, $b));
		}
	} else {
		return $self->_treehash(0,$self->_max());
	}
}

sub maxpower
{
	my ($x) = @_;
	die if $x == 0;
	for (0..31) {
		my $n = 2**$_;
#		return 2**$_ if $n == $x;
		return 2**($_-1)  if ($n >= $x);
	}
}

use List::Util qw/max first/;

sub _find
{
	my ($self, $a) = @_;
	(first { $_->{start} == $a } @{$self->{tree}->[0]} )->{hash};
}
sub _max
{
	my ($self) = @_;
	max map { $_->{start} } @{$self->{tree}->[0]} ;
}

sub get_final_hash
{
	my ($self)  = @_;
	my $ok = $self->{tree}->[ $#{$self->{tree}} ]->[0]->{hash};
	my $new = $self->_treehash();
	die "$ok, $new" unless $ok eq $new;
	#die "OK!";
	return unpack('H*', $self->{tree}->[ $#{$self->{tree}} ]->[0]->{hash} );
}


1;
