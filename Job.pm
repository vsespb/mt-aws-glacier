package Job;

use strict;
use warnings;
use Task;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    return $self;
}

# returns "ok" "wait" "ok subtask" "ok replace"
sub get_task
{
	my ($self) = @_;
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self) = @_;
}
	
1;