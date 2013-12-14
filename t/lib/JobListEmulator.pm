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

package JobListEmulator;
use strict;
use warnings;
use Carp;
use TestUtils;
use JSON::XS 1.00;

sub new
{
	my $class = shift;
	my $self = { seq => 0, markers => {} };
	bless $self, $class;
}

sub _validate_fields
{
	my ($self, $job) = (shift, shift);
	my %j = %$job;
	for (@_) {
		confess unless defined delete $j{$_};
	}
	confess  if keys %j;
}

sub add_page
{
	my $self = shift;
	for my $job (@_) {
		confess unless $job->{Action};
		if ($job->{Action} eq 'ArchiveRetrieval') {
			$self->_validate_fields($job, qw/Action ArchiveId ArchiveSizeInBytes ArchiveSHA256TreeHash Completed CompletionDate CreationDate StatusCode JobId/);
		} elsif ($job->{Action} eq 'InventoryRetrieval') {
			$self->_validate_fields($job, qw/Action Completed CompletionDate CreationDate StatusCode JobId/);
		}

	}
	push @{$self->{pages} }, [@_];
}

sub fetch_page
{
	my ($self, $marker) = @_;

	my $page_index = (defined $marker) ? ($self->{markers}{$marker} || confess "unknown marker $marker") : 0;
	my $new_marker = do {
		if ($page_index < $#{ $self->{pages} } ) {
			my $next_page = $page_index+1;
			$self->{page_to_marker}{$next_page} ||= do {
				my $seq = ++$self->{seq};
				my $m = "marker_$seq";
				$self->{markers}{$m} = $next_page;
				$m;
			}
		} else {
			undef;
		}
	};
	JSON::XS->new->utf8->allow_nonref->pretty->encode({
		JobList => $self->{pages}[$page_index],
		Marker => $new_marker,
	});
}

sub add_archive_fixture
{
	my ($self, $id) = @_;
	$self->add_page(
		map {
			{
				Action => 'ArchiveRetrieval',
				ArchiveId => "archive_${id}_$_",
				ArchiveSizeInBytes => 123+$_,
				ArchiveSHA256TreeHash => "hash$_",
				Completed => JSON_XS_TRUE,
				CompletionDate => 'somedate$_',
				CreationDate => 'somedate$_',
				StatusCode => 'Succeeded',
				JobId => "j_${id}_$_"
			},
		} (1..10)
	);
}


sub add_inventory_fixture
{
	my ($self, $id) = @_;
	$self->add_page(
		map {
			{
				Action => 'InventoryRetrieval',
				Completed => JSON_XS_TRUE,
				CompletionDate => 'somedate$_',
				CreationDate => 'somedate$_',
				StatusCode => 'Succeeded',
				JobId => "j_${id}_$_"
			},
		} (1..10)
	);
}

sub add_inventory_with_date
{
	my ($self, $id, $date) = @_;
	$self->add_page(
		map {
			{
				Action => 'InventoryRetrieval',
				Completed => JSON_XS_TRUE,
				CompletionDate => 'somedate$_',
				CreationDate => $date,
				StatusCode => 'Succeeded',
				JobId => "j_${id}_$_"
			},
		} (1..10)
	);
}


1;
