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