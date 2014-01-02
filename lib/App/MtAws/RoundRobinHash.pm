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

package App::MtAws::RoundRobinHash;

our $VERSION = '1.111';

use strict;
use warnings;
use utf8;
use Carp;

sub new
{
	my ($class) = @_;
	my $self = bless { hash => {}, indices => [], current => undef }, $class;
	$self;
}

sub add
{
	my ($self, $key) = @_;
	if (defined $self->{current}) {
		splice @{ $self->{indices} }, $self->{current}, 0, $key;
		$self->next_key(1);
	} else {
		$self->{current} = 0;
		push @{ $self->{indices} }, $key;
	}
	$self->{hash}{$key} = 1;
}

sub add_to_head
{
	my ($self, $key) = @_;
	if (defined $self->{current}) {
		splice @{ $self->{indices} }, $self->{current}, 0, $key;
		#$self->next_key(1);
	} else {
		$self->{current} = 0;
		push @{ $self->{indices} }, $key;
	}
	$self->{hash}{$key} = 1;
}

sub remove
{
	my ($self, $key) = @_;
	if (defined $self->{current}) {
		my $found = undef;
		for (my $i = 0; $i <= $#{ $self->{indices}}; ++$i) {
			$found = $i, last if ($self->{indices}[$i] eq $key);
		}
		confess unless defined $found;
		--$self->{current} if ($found < $self->{current});
		splice @{ $self->{indices} }, $found, 1;
		if ($#{$self->{indices}} == -1) {
			$self->{current} = undef;
		} elsif ($self->{current} > $#{$self->{indices}}) {
			$self->{current} = 0
		}
		delete $self->{hash}{$key};
	} else {
		confess;
	}
}

sub _new_current
{
	my ($self, $offset) = @_;
	return if $offset > @{$self->{indices}} - 1;
	my $new_current = $self->{current}+$offset;
	$new_current -= @{$self->{indices}} if $new_current > $#{$self->{indices}};
	$new_current;
}

sub next_key
{
	my ($self, $offset) = @_;
	if (defined $self->{current}) {
		defined($self->{current} = $self->_new_current($offset)) or confess;
		$self->{indices}[$self->{current}];
	} else {
		return;
	}
}

sub move_to_tail
{
	my ($self, $offset) = @_;
	if ($offset) {
		my $new_offset = $self->_new_current($offset);
		my $el = splice @{ $self->{indices} }, $new_offset, 1;
		$self->{current}-- if $new_offset < $self->{current};
		splice @{ $self->{indices} }, $self->{current}, 0, $el;
		$self->next_key(1) if @{$self->{indices}} > 1;
	} else {
		$self->next_key(1) if @{$self->{indices}} > 1;
	}
}

sub current
{
	#use Data::Dumper; print Dumper \@_;
	my ($self, $offset) = @_;
	return unless defined $self->{current};
	if ($offset) {
		my $new_current = $self->_new_current($offset);
		return unless defined $new_current;
		$self->{indices}[$new_current];
	} else {
		$self->{indices}[$self->{current}];
	}

}


1;
