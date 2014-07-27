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

package App::MtAws::QueueJob::Download;

our $VERSION = '1.116';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadSegments;
use App::MtAws::QueueJob::DownloadSingle;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	$self->{archive_id}||confess;
	defined($self->{relfilename})||confess;
	defined($self->{filename})||confess;
	$self->{file_downloads}||confess;
	$self->{jobid}||confess;
	$self->{size}||confess;
	defined($self->{mtime})||confess;
	$self->{treehash}||confess;
	$self->enter("download");
}


sub on_download
{
	my ($self) = @_;
	
	my $job = ($self->{file_downloads}{'segment-size'} && $self->{size} > $self->{file_downloads}{'segment-size'}*1048576) ?
		App::MtAws::QueueJob::DownloadSegments->new(map { $_ => $self->{$_} } qw/size archive_id jobid file_downloads relfilename filename mtime/) :
		App::MtAws::QueueJob::DownloadSingle->new(map { $_ => $self->{$_} } qw/archive_id relfilename filename jobid size mtime treehash/);
	return state("wait"), job($job, sub { state("done") });
}

1;
