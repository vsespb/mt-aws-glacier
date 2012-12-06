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

package FileUploadJob;

use strict;
use warnings;
use utf8;
use base qw/Job/;
use FileFinishJob;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    defined($self->{filename})||die;
    defined($self->{relfilename})||die;
    $self->{partsize}||die;
    $self->{upload_id}||die;
    $self->{fh}||die;
    $self->{all_raised} = 0;
    $self->{position} = 0;
    $self->{th} = TreeHash->new();
    return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;
	if ($self->{all_raised}) {
		return ("wait");
	} else {
		my $r = sysread($self->{fh}, my $data, $self->{partsize});
		if (!defined($r)) {
			die;
		} elsif ($r > 0) {
			my $part_th = TreeHash->new(); #TODO: we can sha twice for same data chunk here
			$part_th->eat_data(\$data);
			$part_th->calc_tree();
			
			my $part_final_hash = $part_th->get_final_hash();
			
			my $task = Task->new(id => $self->{position}, action=>"upload_part", data => {
				start => $self->{position},
				upload_id => $self->{upload_id},
				part_final_hash => $part_final_hash,
				filename => $self->{filename}, # TODO: LOG ONLY
			}, attachment => \$data,
			);
			$self->{position} += $r;
			$self->{uploadparts} ||= {};
			$self->{uploadparts}->{$task->{id}} = 1;
			$self->{th}->eat_data(\$data);
			return ("ok", $task);
		} else {
			$self->{all_raised} = 1;
			if (scalar keys %{$self->{uploadparts}} == 0) {
				return ("ok replace", FileFinishJob->new(upload_id => $self->{upload_id}, filesize => $self->{position}, relfilename => $self->{relfilename}, filename => $self->{filename}, th => $self->{th}));
			} else {
				return ("wait");
			}
		}
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	delete $self->{uploadparts}->{$task->{id}};
	if ($self->{all_raised} && scalar keys %{$self->{uploadparts}} == 0) {
		# TODO: $self->{filename} LOG ONLY
		return ("ok replace", FileFinishJob->new(upload_id => $self->{upload_id}, filename => $self->{filename},  relfilename => $self->{relfilename}, filename => $self->{filename}, filesize => $self->{position}, th => $self->{th}));
	} else {
		return ("ok");
	}
}
	
1;