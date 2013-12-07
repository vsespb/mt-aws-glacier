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

our $VERSION = '1.100';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadInventory;
use base 'App::MtAws::QueueJob';
use App::MtAws::Glacier::ListJobs;

sub init
{
	my ($self) = @_;
	$self->{marker} = undef;
	$self->enter("list");
}

sub on_list
{
	my ($self) = @_;
	return state "wait", task "inventory_fetch_job", {  marker => $self->{marker} } => sub {
		my ($args) = @_;

		my ($marker, @jobs) = App::MtAws::Glacier::ListJobs->new( $args->{response} || confess )->get_inventory_entries();
		if (@jobs) {
			my $j = shift @jobs;
			$self->{found_job} = $j->{JobId} || confess;
			return state 'download';
		}
		if ($marker) {
			$self->{marker} = $marker;
			return state 'list';
		} else {
			$self->{inventory_raw_ref} = undef;
			return state 'done';
		}
		
	}
}

sub on_download
{
	my ($self) = @_;
	return state("wait"),
		job( App::MtAws::QueueJob::DownloadInventory->new(job_id => $self->{found_job}||confess), sub {
			my ($j) = @_;
			$self->{inventory_raw_ref} = $j->{inventory_raw_ref} || confess;
			state("done")
		});
}


1;
