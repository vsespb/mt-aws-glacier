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

package App::MtAws::Glacier::ListJobs;

our $VERSION = '1.058';

use strict;
use warnings;
use utf8;

use Carp;
use JSON::XS 1.00;

use App::MtAws::Utils;


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
	$self->{data} ||= JSON::XS->new->allow_nonref->decode(${ delete $self->{rawdata} || confess });
}

#
# Input: ListJobs output
# Output: entries for Inventory retrieval
#
sub get_inventory_entries
{
	my ($self) = @_;
	$self->_parse;
	return $self->{data}{Marker}, map {
		# get rid of JSON::XS boolean object, just in case.
		# also JSON::XS between versions 1.0 and 2.1 (inclusive) do not allow to modify this field
		# (modification of read only error thrown)
		$_->{Completed} = !!(delete $_->{Completed});
		if ($_->{Action} eq 'InventoryRetrieval' && $_->{Completed} && $_->{StatusCode} eq 'Succeeded') {
			$_
		} else {
			();
		}
	} @{$self->{data}{JobList}};
}

1;

