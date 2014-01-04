#!/usr/bin/env perl

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

use strict;
use warnings;
use Test::More tests => 29;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils;
use POSIX;
use App::MtAws::ForkEngine;
use App::MtAws::IntermediateFile;
use Carp;
use Config;
use Time::HiRes qw/usleep/;

# tip for testing this for race conditions:
#
# ( seq 1000 |xargs -P 100 -n 1 ./fork_engine.t  ) && echo ALL_FINE
# test on different Unixes: Linux, FreeBSD and OpenBSD can be different
# under some BSD there is no "seq" but you can use "jot" instead

warning_fatal();

my $rootdir = get_temp_dir();

my @TRUE_CMD = ($Config{'perlpath'}, '-e', '0');

print "# STARTED $$ ".time()."\n";
$SIG{ALRM} = sub { print STDERR "ALARM $$ ".time()."\n"; exit(1) };

sub fork_engine_test($%)
{
	my ($cnt, %cb) = @_;

	no warnings 'redefine';
	local ($SIG{INT}, $SIG{USR1}, $SIG{USR2}, $SIG{TERM}, $SIG{HUP}, $SIG{CHLD});
	local *App::MtAws::ForkEngine::run_children = sub {
		alarm 40;
		my ($self, $out, $in) = @_;
		confess unless $self->{parent_pid};
		$cb{child}->($in, $out, $self->{parent_pid}) if $cb{child};
		alarm 0;
	};
	local *App::MtAws::ForkEngine::run_parent = sub {
		alarm 40;
		my ($self, $disp_select) = @_;
		$cb{parent_init}->($self->{children}) if $cb{parent_init};
		my @ready;
		do { @ready = $disp_select->can_read(); } until @ready || !$!{EINTR};
		for my $fh (@ready) {
			$cb{parent_each}->($fh, $self->{children}) if $cb{parent_each};
		}
		$cb{parent_before_terminate}->($self->{children}) if $cb{parent_before_terminate};
		$self->terminate_children();
		$cb{parent_after_terminate}->() if $cb{parent_after_terminate};
		alarm 0;
	};
	local *App::MtAws::ForkEngine::parent_exit_on_signal = sub {
		my ($self, $sig, $status) = @_;
		$cb{parent_exit_on_signal}->($sig, $status);
	} if ($cb{parent_exit_on_signal});

	my $FE = App::MtAws::ForkEngine->new(options => { concurrency => $cnt});
	$FE->start_children();
}



fork_engine_test 1,
	parent_each => sub {
		my ($fh) = @_;
		is <$fh>, "ready\n";
		system @TRUE_CMD;
		usleep 30_000 for (1..10);
	},
	parent_after_terminate => sub {
		ok 1, "should not die if parent code executed system command";
	},
	child => sub {
		my ($in, $out) = @_;
		print $out "ready\n";

		usleep 10_000 while(1); # waiting for signal to arrive from terminate_children
	};


{
	my @child_signals = (POSIX::SIGUSR2, POSIX::SIGINT, POSIX::SIGHUP, POSIX::SIGTERM);
	my %child_signals;

	for my $sig (@child_signals) {
		my $exited = 0;
		my $filename;
		fork_engine_test 1,
			parent_each => sub {
				my ($fh, $children) = @_;
				$filename = <$fh>;
				chomp $filename;
				ok -f $filename, "child should create temporary file";
				is kill($sig, keys %$children), 1, "kill should work";
				while (!$exited) {
					usleep 30_000;
				}
			},
			parent_exit_on_signal => sub {
				my (undef, $status) = @_;
				$exited = 1;
				$child_signals{$sig} = $status;
			},
			child => sub {
				my ($in, $out) = @_;
				my $I = App::MtAws::IntermediateFile->new(target_file => "$rootdir/child_$$");
				my $filename = $I->tempfilename;
				print $out "$filename\n";
				usleep 30_000 while (1);
			};
		ok $exited, "parent should exit if child receive signal $sig";
		ok !-e $filename, "child should remove temporary files";
	}

	cmp_deeply [values %child_signals], [map { 1 << 8} @child_signals], "all child signals tested";
}


{
	my @unhandled_signals = (POSIX::SIGPIPE, POSIX::SIGUSR1);
	my %child_signals;
	for my $sig (@unhandled_signals) {
		my $exited = 0;
		fork_engine_test 1,
			parent_each => sub {
				my ($fh, $children) = @_;
				my $str = <$fh>;
				is kill($sig, keys %$children), 1, "kill should work";
				while (!$exited) {
					usleep 30_000;
				}
			},
			parent_exit_on_signal => sub {
				my (undef, $status) = @_;
				$exited = 1;
				$child_signals{$sig} = $status;
			},
			child => sub {
				my ($in, $out) = @_;
				print $out "test\n";
				usleep 30_000 while (1);
			};
		ok $exited, "parent should exit if child receive signal $sig";
	}

	cmp_deeply [@child_signals{@unhandled_signals}], [@unhandled_signals], "all child signals tested";
}



my @parent_signals = (POSIX::SIGINT, POSIX::SIGHUP, POSIX::SIGTERM, POSIX::SIGUSR1);
my %parent_signals = map { $_ => 1} @parent_signals;


for my $sig (@parent_signals) { # we dont test SIGCHLD here , this test does not make sense for sighup
	my $wait_test = 0;
	my $exit_flag = 0;
	fork_engine_test 1,
		parent_each => sub { # parent main code - we just wait for exit_flag
			my ($fh, $children) = @_;
			my $childpid = <$fh>;
			chomp $childpid;
			my $out = $children->{$childpid}{tochild};
			print $out "ok\n";

			while (!$exit_flag) {
				usleep 300_000;
			}
		},
		parent_exit_on_signal => sub { # parent signal handler
			$wait_test = 1 if wait() == -1;
			delete $parent_signals{$sig};
			$exit_flag = 1;
		},
		child => sub {
			my ($in, $out, $parent_pid) = @_;
			print $out "$$\n";
			<$in>; # make sure parent already running in main loop
			kill($sig, $parent_pid); # child is killing parent
			while (waitpid($parent_pid, 0) != -1) {};
			usleep 300_000 for (1..30);
		};
	ok($wait_test, "children should be terminated before parent exit due to signal, for signal $sig");
}

ok scalar keys %parent_signals == 0, "all parent signals tested";

1;
