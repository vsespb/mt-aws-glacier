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
	my $read_len = $self->sysreadfull(my $buf, $len);
	$q->{type} = RDWR_DATA;
	$q->{dataref} = \$buf;
	$read_len;
}

sub read
{
	my ($self, $len, $offset) = ($_[0], $_[2], $_[3]);
	$offset ||= 0;
	$_[1] = '' unless defined $_[1];
	if (@{$self->{queue}} && ( my $chunk = $self->{queue}[0] )->{type} == RDWR_DATA) {
		my $chunk_ref = $chunk->{dataref};
		my $chunk_len = length $$chunk_ref;
		if ($len == $chunk_len) {
			shift @{$self->{queue}};
			substr($_[1], $offset) = $$chunk_ref;
			return $len;
		} elsif ($len < $chunk_len) {
			substr($_[1], $offset) = substr($$chunk_ref, 0, $len);
			substr($$chunk_ref, 0, $len)='';
			return $len;
		} elsif ($len > $chunk_len) {
			substr($_[1], $offset) = $$chunk_ref;
			shift @{$self->{queue}};
			return $chunk_len + $self->read($_[1], $len - $chunk_len, $offset + $chunk_len); # works fine for chunk_len==0
		} else {
			confess "never happens";
		}
	} else {
		return $self->SUPER::read($_[1], $len, $offset);
	}
}


1;
