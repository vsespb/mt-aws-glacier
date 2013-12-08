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


# 1) eat_data() for data
# 2) eat_1mb for data
# 3) define_hash
#


# treehash() = treehash(1,7) = sha ( treehash(1,4), teehash(5,7))
# treehash(1,4) = treehash(1,2).treehash(3,4)
# treehash(1,
#


package App::MtAws::TreeHash;

our $VERSION = '1.101';

use strict;
use warnings;
use Digest::SHA qw/sha256/;
use List::Util qw/max/;
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
	while () {
		my $r = read($fh, my $data, $self->{unit});
		if (!defined($r)) {
			die $!;
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

sub eat_data_any_size
{
	my $self = $_[0];
	my $dataref = (ref($_[1]) eq '') ? \$_[1] : $_[1];
	my $mb = $self->{unit};
	my $n = length($$dataref);
	if (defined $self->{buffer}) {
		$self->{buffer} .= $$dataref;
	} else {
		$self->{buffer} = $$dataref;
	}
	if (length($self->{buffer}) == $mb) {
		$self->_eat_data_one_mb($self->{buffer});
		$self->{buffer} = '';
	} elsif (length($self->{buffer}) > $mb) {
		my $i = -0;
		while ($i + $mb <=  length($self->{buffer})) { # TODO this loop for performance optimization, and optimization is not tested
			my $part = substr($self->{buffer}, $i, $mb);
			$self->_eat_data_one_mb($part);
			$i += $mb;
		}
		$self->{buffer} = substr($self->{buffer}, $i);
	}
}

sub eat_another_treehash
{
	my ($self, $th) = @_;
	croak unless $th->isa("App::MtAws::TreeHash");
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
	$self->_eat_data_one_mb($self->{buffer}) if defined($self->{buffer}) && length($self->{buffer});
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


sub calc_tree_recursive
{
	my ($self) = @_;
	my %h = map { $_->{start} => $_ } @{$self->{tree}->[0]};
	$self->{max} = max keys %h;
	$self->{by_position} = \%h;
	
	$self->{treehash_recursive_tree} = $self->_treehash_recursive();
}

sub _treehash_recursive
{
	my ($self, $a, $b) = @_;
	if (defined($a)) {
		if ($a == $b) {
			return $self->{by_position}->{$a}->{hash};
		} else {
			my $middle = _maxpower($b-$a) + $a;
			return sha256 ($self->_treehash_recursive($a, $middle - 1 ).$self->_treehash_recursive($middle, $b));
		}
	} else {
		return $self->_treehash_recursive(0,$self->{max});
	}
}

sub _maxpower
{
	my ($x) = @_;
	die if $x == 0;
	$x |= $x >> 1;
	$x |= $x >> 2;
	$x |= $x >> 4;
	$x |= $x >> 8;
	$x |= $x >> 16;
	$x >>= 1;
	$x++;
	return $x;
}



sub get_final_hash
{
	my ($self)  = @_;
	if (defined $self->{treehash_recursive_tree}) {
		return unpack('H*', $self->{treehash_recursive_tree} );
	} else {
		return unpack('H*', $self->{tree}->[ $#{$self->{tree}} ]->[0]->{hash} );
	}
}


1;
