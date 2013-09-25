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

package App::MtAws::JobIteratorProxy;

our $VERSION = '1.055';

use strict;
use warnings;
use utf8;
use App::MtAws::ProxyTask;
use Carp;

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	$self->{iterator}||die;

	$self->{jobs_h} = {};
	$self->{jobs_a} = [];

	$self->{pending}={};
	$self->{task_autoincrement} = $self->{job_autoincrement} = $self->{iterator_end_of_data} =0;
	bless $self, $class;
	return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;

	while () {
		my $maxcnt = $self->{maxcnt}||30;
		OUTER: for (1) {
			for my $job (@{$self->{jobs_a}}) {
				my ($status, $task) = $job->{job}->get_task();
				if ($status eq 'wait') {
					if ($self->{one_by_one}) {
						return ('wait');
					} else {
						return ('wait') unless --$maxcnt;
					}
				} elsif ($status eq 'done') {
					$self->do_finish($job->{jobid});
					redo OUTER; # TODO: can optimize here..
				} else {
					my $newtask = App::MtAws::ProxyTask->new(id => ++$self->{task_autoincrement}, jobid => $job->{jobid}, task => $task);
					$self->{pending}->{$newtask->{id}} = $newtask;
					return ($status, $newtask);
				}
			}
		}
		my $next_job = $self->{iterator}->();
		if ($next_job) {
			my $i = ++$self->{job_autoincrement};
			$self->{jobs_h}->{$i} = $next_job;
			push @{$self->{jobs_a}}, { jobid => $i, job => $next_job };
			next;
		} else {
			if (@{$self->{jobs_a}}) {
				return ('wait');
			} else {
				return ('done');
			}
		}
	}
}

# returns "ok", "done"
sub finish_task
{
	my ($self, $task) = @_;
	my $jobid = $task->{jobid};
	my $id = $task->{id};

	$task->pop;

	my ($status, @res) = $self->{jobs_h}->{$jobid}->finish_task($task);
	delete $self->{pending}->{$id};

	$self->do_finish($jobid) if ($status eq 'done');
	return ("ok");
}

sub do_finish
{
	my ($self, $jobid) = @_;
	delete $self->{jobs_h}->{$jobid};
	my $idx = 0;
	for my $j (@{$self->{jobs_a}}) {
		if ($j->{jobid} == $jobid) {
			splice(@{$self->{jobs_a}}, $idx, 1);
			last;
		}
		++$idx;
	}
	return 'ok';
}

1;
