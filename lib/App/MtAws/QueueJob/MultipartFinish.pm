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

package App::MtAws::QueueJob::MultipartFinish;

our $VERSION = '1.113';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::Exceptions;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	$self->{upload_id}||confess;
	$self->{filesize}||confess;
	defined($self->{mtime})||confess;
	defined($self->{relfilename})||confess;
	$self->{th}||confess;
	return $self;
}

sub on_default
{
	my ($self) = @_;

	$self->{th}->calc_tree();
	$self->{final_hash} = $self->{th}->get_final_hash();
	return state "wait", task "finish_upload", {
		upload_id => $self->{upload_id},
		filesize => $self->{filesize},
		mtime => $self->{mtime},
		relfilename => $self->{relfilename},
		final_hash => $self->{final_hash}
	} => sub { state "done" };
}

1;
