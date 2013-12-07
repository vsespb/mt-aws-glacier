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

package App::MtAws::QueueJob::VerifyAndUpload;

our $VERSION = '1.100';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Verify;
use App::MtAws::QueueJob::Upload;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	defined($self->{filename})||confess "no filename";
	defined($self->{relfilename}) || confess "no relfilename";
	defined($self->{delete_after_upload}) || confess "delete_after_upload must be defined";
	$self->{partsize}||confess;
	$self->{treehash}||confess;
	if ($self->{delete_after_upload}) {
		confess "archive_id must present if you're deleting" unless $self->{archive_id};
	} else {
		confess "archive_id not needed here" if $self->{archive_id};
	}
	$self->enter("verify");
	return $self;
}


sub on_verify
{
	my ($self) = @_;
	return
		state("wait"),
		job( App::MtAws::QueueJob::Verify->new( map { $_ => $self->{$_} } qw/filename relfilename treehash/ ), sub {
			my $j = shift;
			confess unless defined $j->{match};
			$j->{match} ? state("done") : state("upload");
		});
}


sub on_upload
{
	my ($self) = @_;
	return
		state("wait"),
		job( App::MtAws::QueueJob::Upload->new(map { $_ => $self->{$_} } qw/filename relfilename partsize delete_after_upload archive_id/), sub { # archive_id can be undef
			state("done");
		});
}

sub will_do
{
	my ($self) = @_;
	"Will VERIFY treehash and UPLOAD $self->{filename} if modified";
}

1;
