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

use lib 'lib';

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
	while (1) {
		if ( @{$self->{freeworkers}} ) {
			my ($result, $task) = $ft->get_task();
			if ($result eq 'wait') {
				if (scalar keys %{$self->{children}} == scalar @{$self->{freeworkers}}) {
					die;
				}
				my $r = $self->wait_worker($task_list, $ft, $journal);
				return $r if $r;
			} elsif ($result eq 'ok') {
				my $worker_pid = shift @{$self->{freeworkers}};
				my $worker = $self->{children}->{$worker_pid};
				$task_list->{$task->{id}} = $task;
				send_command($worker->{tochild}, $task->{id}, $task->{action}, $task->{data}, $task->{attachment});
			} else {
				die;
			}
		} else {
			my $r = $self->wait_worker($task_list, $ft, $journal);
			return $r if $r;
		}
	}
}

sub wait_worker
{
	my ($self, $task_list, $ft, $journal) = @_;
	my @ready;
	do { @ready = $self->{disp_select}->can_read(); } until @ready || $! != EINTR;
	for my $fh (@ready) {
		#if (eof($fh)) {
		#	$self->{disp_select}->remove($fh);
		#	die "Unexpeced EOF in Pipe";
		#	next; 
		#}
		my ($pid, $taskid, $data) = get_response($fh);
		push @{$self->{freeworkers}}, $pid;
		die unless my $task = $task_list->{$taskid};
		$task->{result} = $data;
		print "PID $pid $task->{result}->{console_out}\n";
		my ($result) = $ft->finish_task($task);
		delete $task_list->{$taskid};
	
		if ($task->{result}->{journal_entry}) {
			confess unless defined $journal;
			$journal->add_entry($task->{result}->{journal_entry});
		}
		  
		if ($result eq 'done') {
			return $task->{result};
		} 
	}
	return 0;
}

sub send_command
{
	my ($fh, $taskid, $action, $data, $attachmentref) = @_;
    my $data_e = encode_data($data);
    my $attachmentsize = $attachmentref ? length($$attachmentref) : 0;
	my $line = "$taskid\t$action\t$attachmentsize\t$data_e\n";
    
	syswritefull $fh, sprintf("%06d", length $line);
	syswritefull $fh, $line;
	syswritefull $fh, $$attachmentref if $attachmentsize;
}


sub get_response
{
	my ($fh) = @_;
	sysreadfull($fh, my $len, 6);
	sysreadfull($fh, my $line, $len+0);
	
    chomp $line;
    my ($pid, $taskid, $data_e) = split /\t/, $line;
    my $data = decode_data($data_e);
    return ($pid, $taskid, $data);
}


1;
