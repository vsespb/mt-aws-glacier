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

package App::MtAws::RdWr::Readahead;

our $VERSION = '1.111';

use Carp;
use strict;
use warnings;
use utf8;

use constant RDWR_DATA => 3;

use base qw/App::MtAws::RdWr::Read/;


sub readahead
{
	my ($self, $len) = @_;
	return unless $len;
	my $q = {};
	push @{ $self->{queue} }, $q; # buf can be empty here
	$q->{len} = $self->sysreadfull(my $buf, $len);
	$q->{type} = RDWR_DATA;
	$q->{dataref} = \$buf;
}

sub read
{
	my ($self, $len, $offset) = ($_[0], $_[2], $_[3]);
	$offset ||= 0;
	$_[1] = '' unless defined $_[1];
	if (@{$self->{queue}} && (my $first = $self->{queue}[0])->{type} == RDWR_DATA) {
		if ($len == $first->{len}) {
			shift @{$self->{queue}};
			substr($_[1], $offset) = ${$first->{dataref}};
			return $len;
		} elsif ($len < $first->{len}) {
			substr($_[1], $offset) = substr(${$first->{dataref}}, 0, $len);
			substr(${$first->{dataref}}, 0, $len)='';
			return $len;
		} elsif ($len > $first->{len}) {
			substr($_[1], $offset) = ${$first->{dataref}};
			shift @{$self->{queue}};
			return $first->{len} + $self->read($_[1], $len - $first->{len}, $offset + $first->{len}); # works fine for first->len==0
		} else {
			confess "never happens";
		}
	} else {
		return $self->SUPER::read($_[1], $len, $offset);
	}
}


1;
