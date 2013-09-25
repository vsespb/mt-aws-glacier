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

package App::MtAws::FileVersions;

our $VERSION = '1.055';

use strict;
use warnings;
use utf8;

sub new
{
	my ($class) = @_;
	my $self = [];
	bless $self, $class;
	return $self;
}

sub add
{
	my ($self, $o) = @_;
	my $after = $self->_find($o);
	if (defined($after)) {
		splice @$self, $after + 1, 0, $o;
	} else {
		unshift @$self, $o;
	}
}

sub _find
{
	my ($self, $o) = @_;
	my ($start, $end) = (0, $#$self);
	while ($end >= $start) {
		my $mid = _mid($start, $end);
		my $r = _cmp($o, $self->[$mid]);
		if ($r >= 0) {
			if ($mid == $end || _cmp($o, $self->[$mid+1]) < 0) {
				return $mid;
			}
			$start = $mid + 1;
		} else { # $r < 0
			$end = $mid - 1;
		}
	}
	return undef;
}

sub _mid
{
	use integer;
	$_[0] + (($_[1] - $_[0])/2);
}

sub all
{
	my ($self) = @_;
	@$self;
}

sub latest
{
	my ($self) = @_;
	$#$self == -1 ? undef : $self->[-1];
}

# TODO: NOT USED (YET!)
sub delete_by_archive_id
{
	my ($self, $archive_id) = @_;
	for (my $i = 0; $i <= $#$self; ++$i) { # O(n) search !
		if ($self->[$i]{archive_id} eq $archive_id) {
			splice @$self, $i, 1;
			return 1;
		}
	}
	return 0;
}

# alternative 1:

# if mtime defined for both a,b - compare mtime. otherwise compare time
# if mtime equal, compare time too

# when $a->{mtime} <=> $b->{mtime} returns 0 (equal), we magicaly switch to 'time' comparsion
# when $a->{mtime} <=> $b->{mtime} returns 1 or -1, we use that
# ( defined($a->{mtime}) && defined($b->{mtime}) && ($a->{mtime} <=> $b->{mtime}) ) ||
# ( $a->{'time'} <=> $b->{'time'} );

# alternative 2:
# possible alternative formula:
#(defined($a->{mtime}) ? $a->{mtime} : $a->{time}) <=> (defined($b->{mtime}) ? $b->{mtime} : $b->{time})

sub _cmp
{
	my ($a, $b) = @_;
	# use mtime (but if missed, use time) for both values
	(
		(defined($a->{mtime}) ? $a->{mtime} : $a->{time}) # mtime1 or time1
		<=>
		(defined($b->{mtime}) ? $b->{mtime} : $b->{time}) # mtime2 or time2
	) or # if copared values are equal (i.e. mtime1=mtime2 or in some cases mtime1=time2)
	(
		( $a->{'time'} <=> $b->{'time'} ) # compare time
	)
}

1;
