# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2014  Victor Efimov
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

package App::MtAws::ParentWorker;

our $VERSION = '1.113';

use strict;
use warnings;
use utf8;
use App::MtAws::LineProtocol;
use Carp;
use POSIX;
use App::MtAws::Utils;
use base q{App::MtAws::QueueEngine};

sub init
{
	my ($self, %args) = @_;
	$self->{$_} = $args{$_} || confess for (qw/children disp_select options/);
	$self->add_worker($_) for (keys %{$self->{children}});
}

sub queue
{
	my ($self, $worker_id, $task) = @_;
	my $worker = $self->{children}{$worker_id};
	send_data($worker->{tochild}, $task->{action}, $task->{_id}, $task->{args}, $task->{attachment}) or
		$self->comm_error;

}

sub wait_worker
{
	my ($self) = @_;
	my @ready;
	do { @ready = $self->{disp_select}->can_read(); } until @ready || $! != EINTR;
	for my $fh (@ready) {
		my ($pid, undef, $taskid, $data, $resultattachmentref) = get_data($fh);
		$pid or $self->comm_error;

		my $task = $self->unqueue_task($pid);

		confess unless $taskid == $task->{_id};

		$task->{result} = $data;
		$task->{attachmentref} = $resultattachmentref;

		print "PID $pid $data->{console_out}\n";

		$task->{cb_task_proxy}->($data, $resultattachmentref);

		if ($data->{journal_entry}) {
			confess unless defined $self->{journal};
			$self->{journal}->add_entry($data->{journal_entry});
		}
		return;
	}
	return 0;
}

sub process_task
{
	my ($self, $lt, $j) = @_;
	$self->{journal} = $j;
	$self->process($lt);
}

sub comm_error
{
	my ($self) = @_;
	sleep 1; # let's wait for SIGCHLD in order to have same error message in same cases
	kill (POSIX::SIGUSR2, keys %{$self->{children}});
	print STDERR "EXIT eof/error when communicate with child process\n";
	exit(1);
}

1;
