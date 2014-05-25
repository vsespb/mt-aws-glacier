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

package App::MtAws::QueueJob::Iterator;

our $VERSION = '1.115';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;

	$self->{iterator}||confess "iterator required";
	$self->{maxcnt} ||= 30;
	$self->{jobs} = {};
	$self->{job_autoincrement} = 0;
	$self->enter('itt_only');
}


sub get_next_itt
{
	my ($self) = @_;
	my $next_job = $self->{iterator}->();
	if ($next_job) {
		my $i = ++$self->{job_autoincrement};
		$self->{jobs}{$i} = $next_job;
	}
	$next_job;
}

sub find_next_job
{
	my ($self) = @_;
	my $maxcnt = $self->{maxcnt};
	for my $job_id (keys %{$self->{jobs}}) { # Random order of jobs
		my $job = $self->{jobs}{$job_id};
		my $res = $job->next();
		
		# uncoverable branch false count:3
		if ($res->{code} eq JOB_WAIT) {
			return JOB_WAIT unless --$maxcnt;
		} elsif ($res->{code} eq JOB_DONE) {
			delete $self->{jobs}{$job_id};
			return JOB_RETRY;

		} elsif ($res->{code} eq JOB_OK) {
			return task($res->{task}, sub {
				$res->{task}{cb_task_proxy}->(@_);
				return;
			});
		} else {
			# uncoverable statement
			confess;
		}
	}
	return;
}

# there are no pending jobs, only iterator available
sub on_itt_only
{
	my ($self) = @_;

	if ($self->get_next_itt) {
		return state 'itt_and_jobs'; # immediatelly switch to other state
	} else {
		return JOB_DONE;
	}
}


# both jobs and iterator available
sub on_itt_and_jobs
{
	my ($self) = @_;
	if (my @r = $self->find_next_job) { # try to process one pending job
		return @r;
	} elsif ($self->get_next_itt) {
		return JOB_RETRY # otherwise, get new job from iteartor and retry
	} else {
		return state 'jobs_only' # no jobs in iterator? - switch to jobs_only
	}
}

sub on_jobs_only
{
	my ($self) = @_;
	if (my @r = $self->find_next_job) {
		return @r; # can be 'wait' here
	} else {
		return keys %{$self->{jobs}} ? JOB_WAIT : state "done";
	}
}

1;
