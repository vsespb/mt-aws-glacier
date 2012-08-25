package JobListProxy;

use strict;
use warnings;
use ProxyTask;

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
		my $maxcnt = 3;
		for my $job (@{$self->{jobs_a}}) {
			my ($status, $task) = $job->{job}->get_task();
			if ($status eq 'wait') {
				last unless ($maxcnt--);
			} else {
				my $newtask = ProxyTask->new(id => ++$self->{uid}, jobid => $job->{jobid}, task => $task);
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
	
	$task->{task}->{result} = $task->{result}; # TODO: move to ProxyTask
	
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