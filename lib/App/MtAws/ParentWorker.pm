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

package App::MtAws::ParentWorker;

our $VERSION = '1.055';

use strict;
use warnings;
use utf8;
use App::MtAws::LineProtocol;
use Carp;
use POSIX;
use App::MtAws::Utils;

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	$self->{children}||die;
	$self->{disp_select}||die;
	$self->{options}||die;
	@{$self->{freeworkers}} = keys %{$self->{children}};
	bless $self, $class;
	return $self;
}

sub process_task
{
	my ($self, $ft, $journal) = @_;
	my $task_list = {};
	while () {
		if ( @{$self->{freeworkers}} ) {
			my ($result, $task) = $ft->get_task();
			if ($result eq 'wait') {
				if (scalar keys %{$self->{children}} == scalar @{$self->{freeworkers}}) {
					die;
				}
				my ($r, $att) = $self->wait_worker($task_list, $ft, $journal);
				return ($r, $att) if $r;
			} elsif ($result eq 'ok') {
				my $worker_pid = shift @{$self->{freeworkers}};
				my $worker = $self->{children}->{$worker_pid};
				$task_list->{$task->{id}} = $task;
				send_data($worker->{tochild}, $task->{action}, $task->{id}, $task->{data}, $task->{attachment}) or
					$self->comm_error;
			} elsif ($result eq 'done') {
				return (1, undef);
			} else {
				die;
			}
		} else {
			my ($r, $att) = $self->wait_worker($task_list, $ft, $journal);
			return ($r, $att) if $r;
		}
	}
}

sub wait_worker
{
	my ($self, $task_list, $ft, $journal) = @_;
	my @ready;
	do { @ready = $self->{disp_select}->can_read(); } until @ready || $! != EINTR;
	for my $fh (@ready) {
		my ($pid, undef, $taskid, $data, $resultattachmentref) = get_data($fh);
		$pid or $self->comm_error;
		push @{$self->{freeworkers}}, $pid;
		die unless my $task = $task_list->{$taskid};
		$task->{result} = $data;
		$task->{attachmentref} = $resultattachmentref;
		print "PID $pid $task->{result}->{console_out}\n";
		if ($task->{result}->{journal_entry}) {
			confess unless defined $journal;
			$journal->add_entry($task->{result}->{journal_entry});
		}

		delete $task_list->{$taskid};
		my ($result) = $ft->finish_task($task);

		if ($result eq 'done') {
			return ($task->{result}, $task->{attachmentref});
		}
	}
	return 0;
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
