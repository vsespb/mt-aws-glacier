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

package App::MtAws::Glacier::ListJobs;

our $VERSION = '1.112';

use strict;
use warnings;
use utf8;

use Carp;
use JSON::XS 1.00;

use App::MtAws::Utils;
use App::MtAws::MetaData;


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
	return if $self->{data};
	$self->{data} = JSON::XS->new->allow_nonref->decode(${ delete $self->{rawdata} || confess });

	# get rid of JSON::XS boolean object, just in case.
	# also JSON::XS between versions 1.0 and 2.1 (inclusive) do not allow to modify this field
	# (modification of read only error thrown)
	$_->{Completed} = !!(delete $_->{Completed}) for @{$self->{data}{JobList}};
}


sub _completed
{
	$_->{Completed} && $_->{StatusCode} eq 'Succeeded'
}

sub _full_inventory
{
	!(
		$_->{InventoryRetrievalParameters} &&
		(
			defined $_->{InventoryRetrievalParameters}{StartDate} ||
			defined $_->{InventoryRetrievalParameters}{EndDate} ||
			defined $_->{InventoryRetrievalParameters}{Limit} ||
			defined $_->{InventoryRetrievalParameters}{Marker}
		)
	)
}

# TODO: yet unused. release after some time
sub _meta_full_inventory
{
	my ($type) = meta_job_decode($_->{JobDescription});
	$type && $type eq META_JOB_TYPE_FULL;
}

sub _filter_and_return_entries
{
	my ($self, $filter_cb) = @_;
	$self->_parse;
	my $x = \&inventory;
	return $self->{data}{Marker}, grep { $filter_cb->() } @{$self->{data}{JobList}};
}

sub get_inventory_entries
{
	shift->_filter_and_return_entries(sub { $_->{Action} eq 'InventoryRetrieval' && _completed() && _full_inventory() }); #  && _meta_full_inventory()
}

sub get_archive_entries
{
	shift->_filter_and_return_entries(sub { $_->{Action} eq 'ArchiveRetrieval' && _completed() });
}

1;
