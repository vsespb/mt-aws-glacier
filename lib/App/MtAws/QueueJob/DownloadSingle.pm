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

package App::MtAws::QueueJob::DownloadSingle;

our $VERSION = '1.116';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	$self->{archive_id}||confess;
	defined($self->{relfilename})||confess;
	defined($self->{filename})||confess;
	$self->{jobid}||confess;
	$self->{size}||confess;
	defined($self->{mtime})||confess;
	$self->{treehash}||confess;
	$self->enter('download');
}

sub on_download
{
	my ($self) = @_;
	return state "wait", task "retrieval_download_job", {
		(map { $_ => $self->{$_} } qw/archive_id relfilename filename jobid size mtime treehash/),
	} => sub {
		state("done")
	}
}

1;
