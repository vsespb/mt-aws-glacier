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

package MyQueueEngine;

use strict;
use warnings;
use LCGRandom;
use base q{App::MtAws::QueueEngine};
use Carp;

sub init
{
	my ($self, %args) = @_;
	$self->add_worker($_) for (1..$args{n});
}

sub queue { }

sub wait_worker
{
	my ($self) = @_;
	my @possible = $self->get_busy_workers_ids;
	confess unless @possible;
	my $worker_id = $possible[lcg_irand(0, @possible-1)];

	my $task = $self->unqueue_task($worker_id);

	my $method = "on_$task->{action}";
	no strict 'refs';

	my @r = $self->$method(%{$task->{args}});
	$task->{cb_task_proxy}->(@r);
}


1;
