package RetrievalFetchJob;

use strict;
use warnings;
use base qw/Job/;
use FileUploadJob;
use RetrievalDownloadJob;

use JSON::XS;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{archives}||die;
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
		return ("ok", Task->new(id => "retrieval_fetch_job",action=>"retrieval_fetch_job", data => { } ));
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	if ($self->{raised}) {
		my $json = JSON::XS->new->allow_nonref;
		my $scalar = $json->decode( $task->{result}->{response} );
		my @downloads;
		my $seen ={};
		for my $job (@{$scalar->{JobList}}) {
			print "$job->{Completed}|$job->{JobId}|$job->{ArchiveId}\n";
			if ($job->{Completed}) {
				if (my $a = $self->{archives}->{$job->{ArchiveId}}) {
					if (!$seen->{ $job->{ArchiveId} }) {
						$seen->{ $job->{ArchiveId} }=1;
						$a->{jobid} = $job->{JobId};
						push @downloads, $a;
					}
				}
			}
		}
		if (scalar @downloads) {
			return ("ok replace", RetrievalDownloadJob->new(archives=>\@downloads)); #TODO
		} else {
			return ("done");
		}
	} else {
		die;
	}
}
	
1;