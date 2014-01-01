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
	my ($class, $hashref) = @_;
	my $self = bless { source => $hashref, mirror => {}, indices => [], current => undef }, $class;
	$self;
}

sub _addkey
{
	my ($self, $key) = @_;
	if (defined $self->{current}) {
		splice @{ $self->{indices} }, $self->{current}++, 0, $key;
	} else {
		$self->{current} = 0;
		push @{ $self->{indices} }, $key;
	}
	$self->{mirror}{$key} = 1;
}

sub _removekey
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
		delete $self->{mirror}{$key};
	} else {
		confess;
	}
}

sub next_key
{
	my ($self) = @_;
	for (keys %{$self->{source}}) {
		$self->_addkey($_) unless exists $self->{mirror}{$_};
	}
	for (keys %{$self->{mirror}}) {
		$self->_removekey($_) unless exists $self->{source}{$_};
	}
	if (defined $self->{current}) {
		$self->{current} = 0 if ++$self->{current} > $#{$self->{indices}};
		$self->{indices}[$self->{current}];
	} else {
		return;
	}
}

sub next_value
{
	my ($self) = @_;
	my $key = $self->next_key;
	return defined($key) ? $self->{source}{$key} : ();
}

1;
