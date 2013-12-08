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

package App::MtAws::QueueJob::UploadMultipart;

our $VERSION = '1.101';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartCreate;
use App::MtAws::QueueJob::MultipartPart;
use App::MtAws::QueueJob::MultipartFinish;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	defined($self->{filename}) xor $self->{stdin} or confess "filename xor stdin should be specified";
	defined($self->{relfilename}) || confess "no relfilename";
	$self->{partsize}||confess;
	$self->enter("create");
	return $self;
}


sub on_create
{
	my ($self) = @_;
	return
		state("wait"),
		job( App::MtAws::QueueJob::MultipartCreate->new(map { $_ => $self->{$_} } qw/filename stdin relfilename partsize/), sub {
			my $j = shift;
			defined($self->{$_} = $j->{$_}) or confess for qw/fh upload_id mtime/;
			state("part")
		});
}


sub on_part
{
	my ($self) = @_;
	return
		state("wait"),
		job( App::MtAws::QueueJob::MultipartPart->new(map { $_ => $self->{$_} } qw/relfilename partsize mtime upload_id fh/), sub {
			my $j = shift;
			$self->{filesize} = $j->{position} || confess;
			$self->{th} = $j->{th} || confess;
			state("finish")
		});
}

sub on_finish
{
	my ($self) = @_;
	return
		state("wait"),
		job( App::MtAws::QueueJob::MultipartFinish->new(map { $_ => $self->{$_} } qw/upload_id filesize mtime relfilename th/), sub {
			state("done")
		});
}

1;

__END__
