package FileFinishJob;

use strict;
use warnings;
use base qw/Job/;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{upload_id}||die;
    $self->{filesize}||die;
    $self->{filename}||die;
    $self->{relfilename}||die;
    $self->{th}||die;
    $self->{raised} = 0;
    return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;
	if ($self->{raised}) {
		return ("wait");
	} else {
		$self->{raised} = 1;
		$self->{th}->calc_tree();
		$self->{final_hash} = $self->{th}->get_final_hash();
		return ("ok", Task->new(id => "finish_upload",action=>"finish_upload", data => {
			upload_id => $self->{upload_id},
			filesize => $self->{filesize},
			filename => $self->{filename},
			relfilename => $self->{relfilename},
			final_hash => $self->{final_hash}
		} ));
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	if ($self->{raised}) {
		return ("done");
	} else {
		die;
	}
}
	
1;