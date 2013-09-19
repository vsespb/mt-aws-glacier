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

package App::MtAws::QueueEngine;

our $VERSION = '1.051';

use strict;
use warnings;

use Carp;
use App::MtAws::QueueJobResult;

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	$self->{children}||confess;
	$self->{task_inc} = 0;
	@{$self->{freeworkers}} = keys %{$self->{children}};
	$self->{tasks} = undef;
	bless $self, $class;
	return $self;
}

sub unqueue_task
{
	my ($self, $worker_id) = @_;
	my $task_id = delete $self->{children}{$worker_id}{task};
	my $task = delete $self->{tasks}{$task_id} or confess;
	push @{ $self->{freeworkers} }, $worker_id;
	return $task;
}

sub process
{
	my ($self, $job) = @_;
	confess "code is not reentrant" if defined $self->{tasks};
	$self->{tasks} = {};
	while () {
		if (@{ $self->{freeworkers} }) {
			my $res = $job->next;
			if ($res->{code} eq JOB_OK) {
				my $task_id = ++$self->{task_inc};
				$task_id = 1 if $task_id > 1_000_000_000; # who knows..

				my $worker_id = shift @{ $self->{freeworkers} };
				my $task = $res->{task};

				$self->queue($worker_id, $task);

				$self->{tasks}{$task_id} = $task;
				$self->{children}{$worker_id}{task} = $task_id;

			} elsif ($res->{code} eq JOB_WAIT) {
				$self->wait_worker();
			} elsif ($res->{code} eq JOB_DONE) {
				return $job
			} else {
				confess;
			}
		} else {
			$self->wait_worker();
		}
	}
}

1;
