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

package App::MtAws::FileUploadJob;

our $VERSION = '0.981';

use strict;
use warnings;
use utf8;
use base qw/App::MtAws::Job/;
use App::MtAws::FileFinishJob;
use Carp;


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	defined($self->{relfilename})||die;
	$self->{partsize}||die;
	defined($self->{mtime})||die;
	$self->{upload_id}||confess;
	$self->{fh}||die;
	$self->{all_raised} = 0;
	$self->{position} = 0;
	$self->{th} = App::MtAws::TreeHash->new();
	return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;
	if ($self->{all_raised}) {
		return ("wait");
	} else {
		my $r = read($self->{fh}, my $data, $self->{partsize});
		if (!defined($r)) {
			die;
		} elsif ($r > 0) {
			my $part_th = App::MtAws::TreeHash->new(); #TODO: We calc sha twice for same data chunk here
			$part_th->eat_data(\$data);
			$part_th->calc_tree();

			my $part_final_hash = $part_th->get_final_hash();
			my $task = App::MtAws::Task->new(id => $self->{position}, action=>"upload_part", data => {
				start => $self->{position},
				upload_id => $self->{upload_id},
				part_final_hash => $part_final_hash,
				relfilename => $self->{relfilename}
			}, attachment => \$data,
			);
			$self->{position} += $r;
			$self->{uploadparts} ||= {};
			$self->{uploadparts}->{$task->{id}} = 1;
			$self->{th}->eat_data(\$data);
			return ("ok", $task);
		} else {
			confess "Unexpected: zero-size archive" unless ($self->{position});
			$self->{all_raised} = 1;
			if (scalar keys %{$self->{uploadparts}} == 0) {
				# TODO: why do we have to have two FileFinishJob->new ??
				return ("ok replace", App::MtAws::FileFinishJob->new(finish_cb => $self->{finish_cb}, upload_id => $self->{upload_id}, mtime => $self->{mtime}, filesize => $self->{position}, relfilename => $self->{relfilename}, th => $self->{th}));
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
		return ("ok replace", App::MtAws::FileFinishJob->new(finish_cb => $self->{finish_cb}, upload_id => $self->{upload_id}, mtime => $self->{mtime}, relfilename => $self->{relfilename}, filename => $self->{filename}, filesize => $self->{position}, th => $self->{th}));
	} else {
		return ("ok");
	}
}

1;
