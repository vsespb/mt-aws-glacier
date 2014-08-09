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

package App::MtAws::QueueJob::FetchAndDownload;

our $VERSION = '1.120';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Download;
use App::MtAws::QueueJob::Iterator;
use App::MtAws::Glacier::ListJobs;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	$self->{archives}||confess;
	$self->{file_downloads}||confess;
	$self->{downloads} = [];
	$self->{marker} = undef;
	$self->enter("list");
}

sub on_list
{
	my ($self) = @_;
	return state "wait", task "retrieval_fetch_job", {  marker => $self->{marker} } => sub {
		my ($args) = @_;

		my ($marker, @jobs) = App::MtAws::Glacier::ListJobs->new( $args->{response} || confess )->get_archive_entries();
		for (@jobs) {
			if (my $a = $self->{archives}{ $_->{ArchiveId} }) {
				unless ($a->{seen}++) { # TODO: better take latest archives in case of duplicates
					$a->{jobid} = $_->{JobId};
					push @{ $self->{downloads} }, $a;
				}
			}
		}
		if ($marker) {
			$self->{marker} = $marker;
			return state 'list';
		} else {
			return state 'download'; # TODO: or if pending archive list is empty
		}
		
	}
}

sub next_download
{
	my ($self) = @_;
	if (my $rec = shift @{ $self->{downloads}}) {
		return App::MtAws::QueueJob::Download->new( (map { $_ => $rec->{$_}} qw/archive_id filename relfilename size jobid mtime treehash/),
			file_downloads => $self->{file_downloads} );
	} else {
		return;
	}
}

sub on_download
{
	my ($self) = @_;
	
	return state("wait"),
		job( App::MtAws::QueueJob::Iterator->new(iterator => sub { $self->next_download() }), sub {
			state("done")
		});
}


1;
