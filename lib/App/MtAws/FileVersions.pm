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
	my $after = undef;
	for (my $i = $#$self; $i >= 0; --$i) {
		if (_cmp($self->[$i], $o) <= 0) {
			$after = $i;
			last;
		}
	}
	if (defined($after)) {
		for (my $i = $#$self; $i > $after; --$i) {
			$self->[$i+1] = $self->[$i];
		}
		$self->[$after+1] = $o;
	} else {
		unshift @$self, $o;
	}
}

sub _cmp
{
	my ($a, $b) = @_;
	( defined($a->{mtime}) && defined($b->{mtime}) && ($a->{mtime} <=> $b->{mtime}) ) ||
	( $a->{'time'} <=> $b->{'time'} );
}

1;