package ParentWorker;

use LineProtocol;
use strict;
use warnings;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    $self->{children}||die;
    $self->{disp_select}||die;
    @{$self->{freeworkers}} = keys %{$self->{children}};
    bless $self, $class;
    return $self;
}

sub process_task
{
	my ($self, $journal, $ft) = @_;
	my $task_list = {};
	while (1) {
		if ( @{$self->{freeworkers}} ) {
			my ($result, $task) = $ft->get_task();
			if ($result eq 'wait') {
				if (scalar keys %{$self->{children}} == scalar @{$self->{freeworkers}}) {
					die;
				}
				my $r = $self->wait_worker($task_list, , $journal, $ft);
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
			my $r = $self->wait_worker($task_list, $journal, $ft);
			return $r if $r;
		}
	}
}

sub wait_worker
{
	my ($self, $task_list, $journal, $ft) = @_;
	my @ready = $self->{disp_select}->can_read();
    for my $fh (@ready) {
      if (eof($fh)) {
        $self->{disp_select}->remove($fh);
        die "Unexpeced EOF in Pipe";
        next; 
      }
      my ($pid, $taskid, $data) = get_response($fh);
      push @{$self->{freeworkers}}, $pid;
      die unless my $task = $task_list->{$taskid};
      $task->{result} = $data;
      print "PID $pid $task->{result}->{console_out}\n";
      my ($result) = $ft->finish_task($task);
	  delete $task_list->{$taskid};
	  
	  if ($task->{result}->{journal_entry}) {
	  	open F, ">>$journal";
		print F $task->{result}->{journal_entry}."\n";
		close F;
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
    #print ">$line\n";
    print $fh $line;
    print $fh $$attachmentref if $attachmentsize;
}


sub get_response
{
	my ($fh) = @_;
    my $line = <$fh>;
    chomp $line;
   # print "<$line\n";
    my ($pid, $taskid, $data_e) = split /\t/, $line;
    my $data = decode_data($data_e);
    return ($pid, $taskid, $data);
}


1;
