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

package App::MtAws::QueueJob::Upload;

our $VERSION = '1.102';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::UploadMultipart;
use App::MtAws::QueueJob::Delete;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	defined($self->{filename}) xor $self->{stdin} or confess "filename xor stdin should be specified";
	defined($self->{relfilename}) || confess "no relfilename";
	defined($self->{delete_after_upload}) || confess "delete_after_upload must be defined";
	$self->{partsize}||confess;
	if ($self->{delete_after_upload}) {
		confess "archive_id must present if you're deleting" unless $self->{archive_id};
	} else {
		confess "archive_id not needed here" if $self->{archive_id};
	}
	$self->enter("multipart_upload");
	return $self;
}


sub on_multipart_upload
{
	my ($self) = @_;
	return
		state("wait"),
		job( App::MtAws::QueueJob::UploadMultipart->new(map { $_ => $self->{$_} } qw/filename stdin relfilename partsize/), sub {
			$self->{delete_after_upload} ? state("delete") : state("done");
		});
}


sub on_delete
{
	my ($self) = @_;
	return
		state("wait"),
		job( App::MtAws::QueueJob::Delete->new(map { $_ => $self->{$_} } qw/relfilename archive_id/), sub {
			state("done");
		});
}

sub will_do
{
	my ($self) = @_;
	if (defined($self->{filename})) {
		"Will UPLOAD $self->{filename}";
	} elsif ($self->{stdin}) {
		"Will UPLOAD stream from STDIN";
	} else {
		confess;
	}
}

1;
