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

our $VERSION = '1.102';

use strict;
use warnings;

use Carp;
use App::MtAws::QueueJobResult;

sub new
{
	my ($class, %args) = @_;
	my $self = {};
	bless $self, $class;
	$self->{task_inc} = 0;
	$self->{tasks} = undef;
	$self->{freeworkers} = undef;
	$self->{workers} = {};
	$self->init(%args);
	return $self;
}

sub init { confess "Unimplemented" }
sub queue { confess "Unimplemented" }

sub add_worker
{
	my ($self, $worker_id) = @_;
	$self->{workers}{$worker_id} = {};
}

sub unqueue_task
{
	my ($self, $worker_id) = @_;
	my $task_id = delete $self->{workers}{$worker_id}{task};
	my $task = delete $self->{tasks}{$task_id} or confess;
	push @{ $self->{freeworkers} }, $worker_id;
	return $task;
}

sub _next_task_id
{
	my ($self) = @_;
	my $next_id = ++$self->{task_inc};
	$next_id > 0 or confess;
	$next_id;
}

sub process
{
	my ($self, $job) = @_;
	confess "code is not reentrant" if defined $self->{tasks};
	$self->{tasks} = {};
	@{$self->{freeworkers}} = keys %{$self->{workers}};
	while () {
		if (@{ $self->{freeworkers} }) {
			my $res = $job->next;
			if ($res->{code} eq JOB_OK) {
				my $task_id = $self->_next_task_id;

				my $worker_id = shift @{ $self->{freeworkers} };
				my $task = $res->{task};

				$task->{_id} = $task_id;
				$self->queue($worker_id, $task);

				$self->{tasks}{$task_id} = $task;
				$self->{workers}{$worker_id}{task} = $task_id;

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

sub get_busy_workers_ids
{
	my ($self) = @_;
	grep { $self->{workers}{$_}{task} } keys %{ $self->{workers}};
}

1;
