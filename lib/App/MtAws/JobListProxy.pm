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

package App::MtAws::JobListProxy;

use strict;
use warnings;
use utf8;
use App::MtAws::ProxyTask;
use Carp;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    $self->{jobs}||die;
    
    $self->{jobs_h} = {};
    $self->{jobs_a} = [];
    my $i = 1;
    for my $job (@{$self->{jobs}}) {
    	push @{$self->{jobs_a}}, { jobid => $i, job => $job };
    	$self->{jobs_h}->{$i} = $job;
    	++$i;
    }
    
    $self->{pending}={};
    $self->{uid}=0;
    $self->{all_raised} = 0;
    bless $self, $class;
    return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;
	if (scalar @{$self->{jobs_a}}) {
		my $maxcnt = 30;
		for my $job (@{$self->{jobs_a}}) {
			my ($status, $task) = $job->{job}->get_task();
			if ($status eq 'wait') {
				last unless ($maxcnt--);
			} elsif ($status eq 'done') {
				confess;
			} else {
				my $newtask = App::MtAws::ProxyTask->new(id => ++$self->{uid}, jobid => $job->{jobid}, task => $task);
				$self->{pending}->{$newtask->{id}} = $newtask;
				return ($status, $newtask);
			}
		}
		return ('wait');
	} else {
		die;
	}
}

# returns "ok", "done"
sub finish_task
{
	my ($self, $task) = @_;
	my $jobid = $task->{jobid};
	
	$task->{task}->{result} = $task->{result}; # TODO: move to App::MtAws::ProxyTask
	
	my ($status, @res) = $self->{jobs_h}->{$jobid}->finish_task($task->{task});
	delete $self->{pending}->{$task->{id}};
	
	if ($status eq 'ok'){
		return ("ok");
	} elsif ($status eq 'done') {
		delete $self->{jobs_h}->{$jobid};
		my $idx = 0;
		for my $j (@{$self->{jobs_a}}) {
			if ($j->{jobid} == $task->{jobid}) {
				splice(@{$self->{jobs_a}}, $idx, 1);
				last;
			}
			++$idx;
		}
		if (scalar @{$self->{jobs_a}}) {
			return 'ok';
		} else {
			return 'done';
		}
	}
}
	
1;