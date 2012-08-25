package ProxyTask;

use strict;
use warnings;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{task}||die;
    $self->{id}||die;
    $self->{jobid}||die;
    
    $self->{task}->{jobid} = $self->{jobid};
    $self->{action} = $self->{task}->{action};
    $self->{attachment} = $self->{task}->{attachment};
    $self->{data} = $self->{task}->{data};
    $self->{result} = {};
    
    defined($self->{id})||die;
    return $self;
}

	
1;