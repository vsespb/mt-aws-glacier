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

package App::MtAws::Job::InventoryFetch;

our $VERSION = '1.055';

use strict;
use warnings;
use utf8;
use base qw/App::MtAws::Job/;
use App::MtAws::Job::InventoryDownload;

use JSON::XS;


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
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
		return ("ok", App::MtAws::Task->new(id => "inventory_fetch",action=>"inventory_fetch_job", data => { marker => $self->{marker} } ));
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	
	if ($self->{raised}) {
		my $json = JSON::XS->new->allow_nonref;
		my $scalar = $json->decode( $task->{result}->{response} );
		# https://forums.aws.amazon.com/thread.jspa?messageID=421246
		for my $job (@{$scalar->{JobList}}) {
			#print "$job->{Completed}|$job->{JobId}\n";
			if ($job->{Action} eq 'InventoryRetrieval' && $job->{Completed} && $job->{StatusCode} eq 'Succeeded') {
				return ("ok replace", App::MtAws::Job::InventoryDownload->new(job_id => $job->{JobId}));
			}
		}
		
		if ($scalar->{Marker}) {
			return ("ok replace", App::MtAws::Job::InventoryFetch->new(marker => $scalar->{Marker}) );
		} else {
			# TODO: to handle the case when we don't have any inventory retrieved $task->{result}->{response}=undef;
			return ("done");
		}
	} else {
		die;
	}
}
	
1;
