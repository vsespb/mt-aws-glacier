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

package App::MtAws::QueueJob::MultipartCreate;

our $VERSION = '1.111';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::Exceptions;
use App::MtAws::Utils;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	defined($self->{filename}) xor $self->{stdin} or confess "filename xor stdin should be specified";
	defined($self->{relfilename}) || confess "no relfilename";
	$self->{partsize}||confess "no partsize";
	$self->enter('create');
}

sub init_file
{
	my ($self) = @_;
	if ($self->{stdin}) {
		$self->{mtime} = time(); # should be as close as possible to upload process time
		$self->{fh} = *STDIN;
	} else {
		my $filesize = file_size($self->{filename});

		die exception file_is_zero => "File size is zero (and it was not when we read directory listing). Filename: %string filename%",
			filename => $self->{filename}
				unless $filesize;

		$self->{mtime} = file_mtime($self->{filename}); # TODO: how could we assure file not modified when uploading btw?

		die exception too_many_parts =>
			"With current partsize=%d partsize%MiB we will exceed 10000 parts limit for the file %string filename% (file size %size%)",
			partsize => $self->{partsize}, filename => $self->{filename}, size => $filesize
				if ($filesize / $self->{partsize} > 10000);

		open_file($self->{fh}, $self->{filename}, mode => '<', binary => 1) or
			die exception upload_file_open_error => "Unable to open task file %string filename% for reading, errno=%errno%",
				filename => $self->{filename}, 'ERRNO';
	}
}

sub on_create
{
	my ($self) = @_;
	$self->init_file;
	return state "wait", task "create_upload", { partsize => $self->{partsize}, relfilename => $self->{relfilename}, mtime => $self->{mtime} } => sub {
		my ($args) = @_;
		$self->{upload_id} = $args->{upload_id} or confess;
		state("done")
	}
}

1;
