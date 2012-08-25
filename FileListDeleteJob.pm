package FileListDeleteJob;

use strict;
use warnings;
use base qw/Job/;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{archives}||die;
    $self->{pending}={};
    $self->{all_raised} = 0;
    $self->{position} = 0;
    return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;
	if ($self->{all_raised}) {
		return ("wait");
	} else {
		if (scalar @{$self->{archives}}) {
			my $archive = shift @{$self->{archives}};
			my $task = Task->new(id => $archive->{archive_id}, action=>"delete_archive", data => {
				archive_id => $archive->{archive_id}, relfilename => $archive->{relfilename}
			});
			$self->{pending}->{$archive->{archive_id}}=1;
			return ("ok", $task);
		} else {
			$self->{all_raised} = 1;
			return ("wait");
		}
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	delete $self->{pending}->{$task->{id}};
	if ($self->{all_raised} && scalar keys %{$self->{pending}} == 0) {
		return ("done");
	} else {
		return ("ok");
	}
}
	
1;