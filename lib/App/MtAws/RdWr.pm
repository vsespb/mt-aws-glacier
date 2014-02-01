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

package App::MtAws::RdWr;

our $VERSION = '1.113';

use Carp;
use strict;
use warnings;
use utf8;

use constant RDWR_ERROR => 2;

sub new
{
	my ($class, $fh) = @_;
	confess unless $fh;
	my $self = { fh => $fh, queue => [] };
	bless $self, $class;
	return $self;
}

sub _adderror
{
	my ($self, $errno) = @_;
	push @{ $self->{queue} }, { type => RDWR_ERROR, errno => $errno };
}




1;
