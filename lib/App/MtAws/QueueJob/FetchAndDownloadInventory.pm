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

package App::MtAws::QueueJob::FetchAndDownloadInventory;

our $VERSION = '1.056';

use strict;
use warnings;
use Carp;
use JSON::XS;

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadInventory;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
}

sub on_default
{
	my ($self) = @_;
	return state "wait", task "inventory_fetch_job", {  marker => $self->{marker} } => sub {
		my ($args) = @_;
		defined($self->{response} = $args->{response}) || confess;
		state("parsing")
	}
}

sub on_parsing
{
	my ($self) = @_;
	my $json = JSON::XS->new->allow_nonref;
	my $scalar = $json->decode( $self->{response} );
	for my $job (@{$scalar->{JobList}}) {
		if ($job->{Action} eq 'InventoryRetrieval' && $job->{Completed} && $job->{StatusCode} eq 'Succeeded') {
			# we found inventory on current job listing page
			
			# run download inventory task
			return state("wait"),
				job( App::MtAws::QueueJob::DownloadInventory->new(job_id => $job->{JobId}), sub {
					my ($j) = @_;
					confess unless exists $j->{inventory_raw_ref};
					$self->{inventory_raw_ref} = $j->{inventory_raw_ref}; # and set it's result as our result
					state("done")
				});
		}
	}
	
	# we did not find inventory on current job listing page
	
	if ($scalar->{Marker}) {
		# we go next page
		return state("wait"),
			job( App::MtAws::QueueJob::FetchAndDownloadInventory->new(marker => $scalar->{Marker}), sub {
				my ($j) = @_;
				confess unless exists $j->{inventory_raw_ref};
				$self->{inventory_raw_ref} = $j->{inventory_raw_ref}; # propogate result
				state("done")
			});
	} else {
		# there are no (more) pages
		$self->{inventory_raw_ref} = undef; # return undef instead of ref
		state("done")
	}
}

1;
