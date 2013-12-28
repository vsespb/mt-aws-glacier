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


=pod

$rd->readahead($len)

Reads up to $len bytes from real stream to readahead buffers. Return number of bytes read. (unlike perl sysread,
0 in case of both eof and errors).

If there was already data in readahead buffer, it does not change behaviour of readahead()

=cut

sub readahead
{
	my ($self, $len) = @_;
	return 0 unless $len;
	my $q = {};
	push @{ $self->{queue} }, $q; # buf can be empty here
	my $read_len = $self->sysreadfull(my $buf, $len); # can be undef
	$q->{type} = RDWR_DATA;
	$q->{dataref} = \$buf;
	$read_len||0;
}

sub read
{
	my ($self, $len, $offset) = ($_[0], $_[2], $_[3]);
	$offset = $self->_initialize_buffer($_[1], $offset);
	my $add_length = 0;
	# TODO: while loop works only if we assume that there is only RDWR_DATA, RDWR_EOF/ERR and later can be in the end only.
	while (@{$self->{queue}} && ( my $chunk = $self->{queue}[0] )->{type} == RDWR_DATA) {
		my $chunk_ref = $chunk->{dataref};
		my $chunk_len = length $$chunk_ref;
		if ($len < $chunk_len) {
			substr($_[1], $offset) = substr($$chunk_ref, 0, $len);
			substr($$chunk_ref, 0, $len)='';
			return $add_length + $len;
		} elsif ($len > $chunk_len) {
			substr($_[1], $offset) = $$chunk_ref;
			shift @{$self->{queue}};
			# works fine for chunk_len==0
			$add_length += $chunk_len;
			$offset += $chunk_len;
			$len -= $chunk_len;
		} else { # $len == $chunk_len
			shift @{$self->{queue}};
			substr($_[1], $offset) = $$chunk_ref;
			return $add_length + $len;
		}
	}
	my $real_read = $self->SUPER::read($_[1], $len, $offset);
	return $add_length ? $add_length + ($real_read||0) : $real_read; # real_read can be undef
}


1;
