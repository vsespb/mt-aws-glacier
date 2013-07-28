#!/usr/bin/perl

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

use strict;
use warnings;
use Test::More tests => 19;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use TestUtils;
use POSIX;
use App::MtAws::ForkEngine;
use Carp;
use Config;
use Time::HiRes qw/usleep/;

warning_fatal();

my $rootdir = get_temp_dir();

my @TRUE_CMD = ($Config{'perlpath'}, '-e', '0');

sub fork_engine_test($%)
{
	my ($cnt, %cb) = @_;

	no warnings 'redefine';
	local ($SIG{INT}, $SIG{USR1}, $SIG{USR2}, $SIG{TERM}, $SIG{HUP}, $SIG{CHLD});
	local *App::MtAws::ForkEngine::run_children = sub {
		my ($self, $out, $in) = @_;
		$cb{child}->($in, $out) if $cb{child};
	};
	local *App::MtAws::ForkEngine::run_parent = sub {
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
	};
	local *App::MtAws::ForkEngine::parent_exit_on_signal = sub {
		my ($self, $sig) = @_;
		$cb{parent_exit_on_signal}->($sig);
	} if ($cb{parent_exit_on_signal});

	my $FE = App::MtAws::ForkEngine->new(options => { concurrency => $cnt});
	$FE->start_children();
}

fork_engine_test 1,
	parent_each => sub {
		my ($fh) = @_;
		is <$fh>, "ready\n";
		system @TRUE_CMD;
		usleep 300_000;
	},
	parent_after_terminate => sub {
		ok 1, "should not die if parent code executed system command";
	},
	child => sub {
		my ($in, $out) = @_;
		print $out "ready\n";
		<$in>;
	};


my @child_signals = (POSIX::SIGINT, POSIX::SIGHUP, , POSIX::SIGTERM, POSIX::SIGUSR2);
my %child_signals = map { $_ => 1} @child_signals;

for my $sig (@child_signals) {
	ok $sig, "testing $sig";
	fork_engine_test 1,
		parent_each => sub {
			my ($fh, $children) = @_;
			is <$fh>, "ready\n";
			is kill($sig, keys %$children), 1;
			sleep 10;
		},
		parent_exit_on_signal => sub {
			ok 1, "parent should exit if child receive signal $sig";
			delete $child_signals{$sig};
		},
		child => sub {
			my ($in, $out) = @_;
			print $out "ready\n";
			<$in>;
		};
}

ok scalar keys %child_signals == 0, "all child signals tested";

1;
