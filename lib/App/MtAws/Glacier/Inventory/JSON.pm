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

package App::MtAws::Glacier::Inventory::JSON;

our $VERSION = '1.112';

use strict;
use warnings;
use utf8;

use Carp;
use JSON::XS 1.00;

use App::MtAws::Glacier::Inventory ();
use base q{App::MtAws::Glacier::Inventory};

sub new
{
	my $class = shift;
	my $self = { rawdata => \$_[0] };
	bless $self, $class;
	$self;
}

sub _parse
{
	my ($self) = @_;
	$self->{data} = JSON::XS->new->allow_nonref->utf8->decode(${ delete $self->{rawdata} || confess });
}

1;
