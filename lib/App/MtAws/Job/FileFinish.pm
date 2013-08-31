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

package App::MtAws::Job::FileFinish;

our $VERSION = '1.050';

use strict;
use warnings;
use utf8;
use base qw/App::MtAws::Job/;


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->{upload_id}||die;
	$self->{filesize}||die;
	defined($self->{mtime})||die;
	defined($self->{relfilename})||die;
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
		return ("ok", App::MtAws::Task->new(id => "finish_upload",action=>"finish_upload", data => {
			upload_id => $self->{upload_id},
			filesize => $self->{filesize},
			mtime => $self->{mtime},
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
		if ($self->{finish_cb}) {
			return ("ok replace", $self->{finish_cb}->($task));
		} else {
			return ("done");
		}
	} else {
		die;
	}
}
	
1;
