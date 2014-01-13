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

package App::MtAws::ForkEngine;

our $VERSION = '1.112';

use strict;
use warnings;
use utf8;
use IO::Select;
use IO::Pipe;
use IO::Handle;
use Carp;
use App::MtAws::ChildWorker;
use App::MtAws::ParentWorker;
use App::MtAws::Utils;
use App::MtAws::Exceptions;
use POSIX;

require Exporter;
use base qw/Exporter/;

our @EXPORT_OK = qw/with_forks fork_engine/;

# some DSL

our $FE = undef;

sub fork_engine()
{
	$FE||confess;
}

sub with_forks($$&)
{
	my ($flag, $options, $cb) = @_;
	local $FE = undef;
	if ($flag) {
		$FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		if (defined eval {$cb->(); 1;}) {
			$FE->terminate_children();
		} else {
			dump_error(q{parent});
			$FE->terminate_children();
			exit(1);
		}
	} else {
		$cb->();
	}
}

# class

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

sub run_children
{
	my ($self, $child_fromchild, $child_tochild) = @_;
	my $C = App::MtAws::ChildWorker->new(options => $self->{options}, fromchild => $child_fromchild, tochild => $child_tochild);
	dump_error("child $$") unless (defined eval {$C->process(); 1;});
}

sub run_parent
{
	my ($self, $disp_select) = @_;
	return $self->{parent_worker} = App::MtAws::ParentWorker->new(children => $self->{children}, disp_select => $disp_select, options=>$self->{options});
}

sub parent_exit_on_signal
{
	my ($self, $sig, $status) = @_;
	my $status_str = do {
		if (defined $status) {
			my $exit_code = $status >> 8;
			my $signal = $status & 127;
			if ($signal) {
				" (signal $signal, exit_code $exit_code)";
			} else {
				" (exit_code $exit_code)";
			}
		} else {
			"";
		}
	};
	print STDERR "\nEXIT on SIG$sig$status_str\n";
	exit(1);
}

sub start_children
{
	my ($self) = @_;
	# parent's data
	my $disp_select = IO::Select->new();
	$self->{parent_pid} = $$;
	# child/parent code
	for my $n (1..$self->{options}->{concurrency}) {
		my ($ischild, $child_fromchild, $child_tochild) = $self->create_child($disp_select);
		if ($ischild) {
			# child code
			my $first_time = 1;
			my @signals = qw/INT TERM USR2 HUP/;
			for my $sig (@signals) {
				$SIG{$sig} = sub {
					if ($first_time) {
						$first_time = 0;
						exit(1); # we need exit, it will call all destructors which will destroy tempfiles
					}
				};
			}
			$self->run_children($child_fromchild, $child_tochild);
			exit(1);
		}
	}

	my $first_time = 1;
	for my $sig (qw/INT TERM CHLD USR1 HUP/) {
		$SIG{$sig} = sub {
			local ($!,$^E,$@);
			my $status = undef;
			if ($sig eq 'CHLD') {
				my $pid = waitpid(-1, WNOHANG);
				$status = $?;
				# make sure we caugth signal from our children, not from external command executionin 3rd party module
				# easy to test by adding `whoami` to parent after-fork-code
				return unless $pid > 0 and defined delete $self->{children}{$pid}; # we also remove $pid
			}
			if ($first_time) {
				$first_time = 0;
				kill (POSIX::SIGUSR2, keys %{$self->{children}});
				while( wait() != -1 ){};
				$self->parent_exit_on_signal($sig, $status);
			}
		};
	}

	return $self->run_parent($disp_select);
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
		$|=1;
		STDERR->autoflush(1);
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
		$|=1;
		STDERR->autoflush(1);
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
	$SIG{CHLD} = 'DEFAULT'; # don't set SIGCHLD to IGNORE, prevents wait() from working under 5.12.2,3 undef OpenBSD
	$SIG{INT} = $SIG{USR2}='IGNORE';

	# close all pipes, just in case select() in child is not interruptable (seems it is under 5.14.2?)
	# https://rt.perl.org/Ticket/Display.html?id=93428
	for (values %{$self->{children}}) {
		close $_->{fromchild};
		close $_->{tochild};
	}
	kill (POSIX::SIGUSR2, keys %{$self->{children}}); # TODO: we terminate all children with SIGUSR2 even on normal exit
	$SIG{TERM} = 'DEFAULT';
	while( wait() != -1 ){};
}
1;
