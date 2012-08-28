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

package TreeHash;

use strict;
use warnings;
use Digest::SHA qw/sha256/;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    $self->{tree} = [];
    $self->{pending} = {};
    $self->{processed_size} = 0; # MB
    bless $self, $class;
    return $self;
}


sub eat_file
{
	my ($self, $fh) = @_;
	while (1) {
		my $r = sysread($fh, my $data, 1048576);
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
	my ($self, $dataref)  = @_;
	my $mb = 1048576;
	my $n = length($$dataref);
	my $i = 0;
	while ($i < $n) {
		my $part = substr($$dataref, $i, $mb);
		$self->_eat_data_one_mb(\$part);
		$i += $mb
	}
}


sub _eat_data_one_mb
{
	my ($self, $dataref)  = @_;
	$self->{tree}->[0] ||= [];
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


sub get_final_hash
{
	my ($self)  = @_;
	return unpack('H*', $self->{tree}->[ $#{$self->{tree}} ]->[0]->{hash} );
}


1;
