package JobProxy;

use strict;
use warnings;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    $self->{job}||die;
    bless $self, $class;
    return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self, @a) = @_;
	my @r = $self->{job}->get_task(@a);
	
	if ($r[0] eq 'ok replace'){
		$self->{job} = $r[1];
		 @r = $self->{job}->get_task(@a);
	}
	return @r;
}

# returns "ok", "done"
sub finish_task
{
	my ($self, @a) = @_;
	my @res = $self->{job}->finish_task(@a);
	if ($res[0] eq 'ok replace'){
		$self->{job} = $res[1];
		return ("ok");
	} else {
		return @res;
	}
}
	
1;