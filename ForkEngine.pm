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

package ForkEngine;

use strict;
use warnings;
use utf8;
use IO::Select;
use IO::Pipe;
use ChildWorker;
use ParentWorker;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    $self->{options}||die;
	$self->{children} = {};
#    $self->{disp_select}||die;
#    @{$self->{freeworkers}} = keys %{$self->{children}};
    bless $self, $class;
    return $self;
}

sub start_children
{
	my ($self) = @_;
	# parent's data
	my $disp_select = IO::Select->new();
	my $parent_pid = $$;
	# child/parent code
	for my $n (1..$self->{options}->{concurrency}) {
		my ($ischild, $child_fromchild, $child_tochild) = $self->create_child($disp_select);
		if ($ischild) {
			$SIG{INT} = $SIG{TERM} = sub { kill(12, $parent_pid); print STDERR "CHILD($$) SIGINT\n"; exit(1); };
			$SIG{USR2} = sub { exit(0); };
			# child code
			my $C = ChildWorker->new(options => $self->{options}, fromchild => $child_fromchild, tochild => $child_tochild);
			$C->process();
			kill(2, $parent_pid);
			exit(1);
		}
	}
	$SIG{INT} = $SIG{TERM} = $SIG{CHLD} = sub { $SIG{CHLD}='IGNORE';kill (12, keys %{$self->{children}}) ; print STDERR "PARENT Exit\n"; exit(1); };
	$SIG{USR2} = sub {  $SIG{CHLD}='IGNORE';print STDERR "PARENT SIGUSR2\n"; exit(1); };
	return $self->{parent_worker} = ParentWorker->new(children => $self->{children}, disp_select => $disp_select, options=>$self->{options});
}

#
# child/parent code
#
sub create_child
{
  my ($self, $disp_select) = @_;
  
  my $fromchild = new IO::Pipe;
  #log("created fromchild pipe $!", 10) if level(10);
  my $tochild = new IO::Pipe;
  #log("created tochild pipe $!", 10) if level(10);
  my $pid;
  my $parent_pid = $$;
  
  if($pid = fork()) { # Parent
   
   $fromchild->reader();
   $fromchild->autoflush(1);
   $fromchild->blocking(1);
   binmode $fromchild;
   
   $tochild->writer();
   $tochild->autoflush(1);
   $tochild->blocking(1);
   binmode $tochild;
    
   $disp_select->add($fromchild);
   $self->{children}->{$pid} = { pid => $pid, fromchild => $fromchild, tochild => $tochild };
   
   print "PID $pid Started worker\n";
   return (0, undef, undef);
  } elsif (defined ($pid)) { # Child

   $fromchild->writer();
   $fromchild->autoflush(1);
   $fromchild->blocking(1);
   binmode $fromchild; 

   $tochild->reader();
   $tochild->autoflush(1);
   $tochild->blocking(1);
   binmode $tochild;

   
   undef $disp_select; # we discard tonns of unneeded pipes !
   undef $self->{children};
   
  
   return (1, $fromchild, $tochild);
  } else {
  	die "Cannot fork()";
  }
}


sub terminate_children
{
	my ($self) = @_;
	$SIG{INT} = $SIG{TERM} = $SIG{CHLD} = $SIG{USR2}='IGNORE';
	kill (12, keys %{$self->{children}});
	while(wait() != -1) { print STDERR "wait\n";};
	print STDERR "OK DONE\n";
	exit(0);
}
1;
