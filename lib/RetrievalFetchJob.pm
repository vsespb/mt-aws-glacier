# mt-aws-glacier - AWS Glacier sync client
# Copyright (C) 2012  Victor Efimov
# vs@vs-dev.com http://vs-dev.com
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
		#$scalar->{Marker};
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