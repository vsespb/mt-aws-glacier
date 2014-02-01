# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2014  Victor Efimov
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

package App::MtAws::RdWr::Read;

our $VERSION = '1.113';

use Carp;
use strict;
use warnings;
use utf8;

use base qw/App::MtAws::RdWr/;

use constant RDWR_EOF => 1;

sub new
{
	my ($class, $fh) = @_;
	confess unless $fh;
	my $self = { fh => $fh, queue => [] };
	bless $self, $class;
	return $self;
}

sub _addeof
{
	push @{ shift->{queue} }, { type => RDWR_EOF };
}


sub read_exactly
{
	my ($self, $len, $offset) = ($_[0], $_[2], $_[3]);
	$self->read($_[1], $len, $offset) == $len;
}

sub _sysread
{
	sysread($_[0], $_[1], $_[2], $_[3])
}

sub sysreadfull
{
	my ($self, $len, $offset) = ($_[0], $_[2], $_[3]);
	confess unless $len;
	$offset ||= 0;
	my $n = 0;
	while ($len - $n) {
		confess if $len - $n < 0;
		my $i = _sysread($self->{fh}, $_[1], $len - $n, $offset + $n);
		if (defined($i)) {
			if ($i == 0) {
				$self->_addeof();
				return $n;
			} else {
				$n += $i;
			}
		} elsif ($!{EINTR}) {
			redo;
		} else {
			$self->_adderror($!+0);
			return $n ? $n : undef;
		}
	}
	return $n;
}

sub was_eof
{
	my $self = shift;
	!! ( @{$self->{queue}} && $self->{queue}[0]{type} == RDWR_EOF );
}

sub _initialize_buffer
{
	my ($self, $offset) = ($_[0], $_[2]);
	$offset ||= 0;
	$_[1] = '' unless defined $_[1];
	my $delta = $offset - length $_[1];
	$_[1] .= "\x00" x $delta if $delta > 0;
	$offset
}

sub read
{
	my ($self, $len, $offset) = ($_[0], $_[2], $_[3]);
	$offset = $self->_initialize_buffer($_[1], $offset);
	if (@{$self->{queue}}) {
		my $first = $self->{queue}[0];
		if ($first->{type} == App::MtAws::RdWr::RDWR_ERROR) {
			$! = $first->{errno};
			return undef;
		} elsif ($first->{type} == RDWR_EOF) {
			return 0;
		} else {
			confess "unknown type $first->{type}";
		}
	} else {
		return $self->sysreadfull($_[1], $len, $offset);
	}
}

1;
