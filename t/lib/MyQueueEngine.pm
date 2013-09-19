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

sub new
{
	my ($class, $n) = @_;
	my $self = $class->SUPER::new(children => {map { $_ => {} } (1..$n) });
	$self;
}

sub queue
{
	my ($self, $worker_id, $task_id, $task) = @_;
	$self->{children}{$worker_id}{task} = $task_id;
}

sub wait_worker
{
	my ($self, $tasks) = @_;
	my @possible = grep { $self->{children}{$_}{task} } keys %{ $self->{children}};

	confess unless @possible;
	my $rr = lcg_irand(0, @possible-1);
	my $r = $possible[$rr];
	my $t_id = delete $self->{children}{$r}{task};
	my $t = delete $tasks->{$t_id} or confess;
	push @{ $self->{freeworkers} }, $r;
	my $method = "on_$t->{action}";
	no strict 'refs';

	my @r = $self->$method(%{$t->{args}});
	$t->{cb_task_proxy}->(@r);
}


1;
