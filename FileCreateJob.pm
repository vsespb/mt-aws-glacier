package FileCreateJob;

use strict;
use warnings;
use base qw/Job/;
use FileUploadJob;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{filename}||die;
    $self->{relfilename}||die;
    $self->{partsize}||die;
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
	    open my $fh, "<$self->{filename}";
	    binmode $fh;
	    $self->{fh} = $fh;
		return ("ok", Task->new(id => "create_upload",action=>"create_upload", data => { partsize => $self->{partsize}} ));
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	if ($self->{raised}) {
		return ("ok replace", FileUploadJob->new(fh => $self->{fh}, relfilename => $self->{relfilename}, filename => $self->{filename}, partsize => $self->{partsize}, upload_id => $task->{result}->{upload_id}));
	} else {
		die;
	}
}
1;