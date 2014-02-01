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

package App::MtAws::RdWr::Write;

our $VERSION = '1.113';

use Carp;
use strict;
use warnings;
use utf8;

use base qw/App::MtAws::RdWr/;
use App::MtAws::Utils qw/is_wide_string/;


sub _syswrite
{
	syswrite($_[0], $_[1], $_[2], $_[3])
}

sub write_exactly
{
	my $length = length $_[1];
	syswritefull(@_) == $length
}

sub syswritefull
{
	my ($self, $len) = ($_[0], length($_[1]));

	confess "upgraded strings not allowed" if is_wide_string($_[1]);
	my $n = 0;
	while ($len - $n) {
		my $i = _syswrite($self->{fh}, $_[1], $len - $n, $n);
		if (defined($i)) {
			$n += $i;
		} elsif ($!{EINTR}) {
			redo;
		} else {
			$self->_adderror($!+0);
			return $n ? $n : undef;
		}
	}
	return $n;
}


1;
