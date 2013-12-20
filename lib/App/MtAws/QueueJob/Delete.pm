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

package App::MtAws::QueueJob::Delete;

our $VERSION = '1.110';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	defined($self->{relfilename}) || confess "no relfilename";
	$self->{archive_id} || confess;
	$self->enter('delete');
}

sub on_delete
{
	my ($self) = @_;
	return state "wait", task "delete_archive", { archive_id => $self->{archive_id}, relfilename => $self->{relfilename} } => sub {
		state("done")
	}
}

sub will_do
{
	my ($self) = @_;
	"Will DELETE archive $self->{archive_id} (filename $self->{relfilename})";
}

1;
