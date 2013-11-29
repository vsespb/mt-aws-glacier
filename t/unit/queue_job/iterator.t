#!/usr/bin/env perl

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
use Test::More;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use List::Util qw/min max/;
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Iterator;
use App::MtAws::QueueJob::MultipartPart;
use QueueHelpers;
use TestUtils;
use LCGRandom;

warning_fatal();


use Data::Dumper;

{
	package SimpleJob;
	use Carp;
	use App::MtAws::QueueJobResult;use Data::Dumper;
	use base 'App::MtAws::QueueJob';
	sub init {  };

	sub on_default
	{
		state 'wait', task($_[0]->{action}, {x => $_[0]->{n}}, sub {
			confess unless $_[0] && $_[0] =~ /^somedata\d$/;
			state 'done'
		});
	};

}

{
	package QE;
	use MyQueueEngine;
	use base q{MyQueueEngine};

	our $AUTOLOAD;

	sub AUTOLOAD
	{
		my $action = $AUTOLOAD;
		$action =~ s/^.*::on_//;
		my $self = shift;
		push @{$self->{res}}, { action => $action, data => [@_] };
		"somedata0"
	}
};

sub action_str
{
	"abc".join('', (map { sprintf("%04d", $_)  } @_));
}

sub create_iterator
{
	my ($maxcnt, $cnt, $jobs_count, $cb, @actions) = @_;

	my @orig_parts  = do {
		if ($jobs_count == 1) {
			map {
				my $a = action_str(@actions, $_);
				my $x = "x$a";
				SimpleJob->new(action => $a, n => $x)
			} (1..$cnt);
		} else {
			map { create_iterator($jobs_count+1, $jobs_count, 1, undef, @actions, $_) } (1..$cnt);
		}

	};
	App::MtAws::QueueJob::Iterator->new(maxcnt => $maxcnt, iterator => sub {
		$cb->() if $cb;
		@orig_parts ? shift @orig_parts : ()
	});
}

sub test_case_early_finish
{
	my ($maxcnt, $cnt, $jobs_count) = @_;

	my $live_counter = 0;
	my @live_counter_log;
	my $itt = create_iterator($maxcnt, $cnt, $jobs_count, sub { ++$live_counter });
	my @actions;
	while (1) {
		my $r = $itt->next;
		push @live_counter_log, $live_counter;
		ok $r->{code} eq JOB_OK || $r->{code} eq JOB_DONE;
		last if $r->{code} eq JOB_DONE;
		push @actions, $r->{task}{action};
		$r->{task}{cb_task_proxy}->("somedata1");
	}

	cmp_deeply [@live_counter_log], [map { $_ } 1..$cnt+1], "should not call itterator for all jobs at once";
	cmp_deeply [sort @actions], [sort map { action_str($_) } 1..$cnt], "test it works when callback called immediately";

}

sub test_late_finish
{
	my ($maxcnt, $cnt, $jobs_count) = @_;

	my $live_counter = 0;
	my @live_counter_log;
	my $itt = create_iterator($maxcnt, $cnt, $jobs_count, sub { ++$live_counter });
	my @actions = ();
	my @passes;
	while (@actions < $cnt) {
		my @callbacks = ();
		my $r;
		while (1) {
			$r = $itt->next;
			push @live_counter_log, $live_counter;
			ok $r->{code} eq JOB_OK || $r->{code} eq JOB_WAIT;
			last if $r->{code} eq JOB_WAIT;
			push @actions, $r->{task}{action};
			push @callbacks, $r->{task}{cb_task_proxy};
		}
		if ($r->{code} eq JOB_WAIT) {
			push @passes, scalar @callbacks;
			$_->("somedata2") for @callbacks;
			next;
		}
	}
	cmp_deeply [sort @actions], [sort map { action_str($_) } 1..$cnt];
	#print Dumper $maxcnt, $cnt, \@live_counter_log;

	if ($cnt % $maxcnt) {
		cmp_deeply {map { $_ => 1 } @live_counter_log}, {map { $_ => 1 } 1..$cnt+1}, "should not call itterator for all jobs at once";
	} else {
		cmp_deeply {map { $_ => 1 } @live_counter_log}, {map { $_ => 1 } 1..$cnt  }, "should not call itterator for all jobs at once";
	}

	is pop @passes, $cnt % $maxcnt, "last pass should contain cnt mod maxcnt items" if ($cnt % $maxcnt);
	is $_, $maxcnt, "all passes excapt last should contain maxcnt items (if more than one pass)" for (@passes);
	is $itt->next->{code}, JOB_DONE, "test it works when callback called later";

	is $live_counter, $cnt+1;
}

sub test_random_finish
{
	my ($maxcnt, $cnt, $jobs_count, $nworkers) = @_;
	my $itt = create_iterator($maxcnt, $cnt, $jobs_count);
	my $q = QE->new(n => $nworkers);
	$q->process($itt);

	for (@{ $q->{res} }) {
		ok $_->{action} =~ /^abc(\d{4})/;
		is $_->{data}[0], 'x';
		ok $_->{data}[1] =~ /^xabc$1/;
		is scalar @{ $_->{data} }, 2;
	}
	if ($jobs_count == 1) {
		cmp_deeply [sort map { $_->{action} } @{ $q->{res} }], [sort map { action_str($_) } 1..$cnt];
	} else {
		is scalar @{ $q->{res} }, $cnt*$jobs_count;
	}
}

plan_tests 928 => sub {

	ok ! eval { App::MtAws::QueueJob::Iterator->new(maxcnt => 30); 1; };
	like $@, qr/iterator required/;

	{
		my $itt = App::MtAws::QueueJob::Iterator->new(maxcnt => 20, iterator => sub {});
		is $itt->{maxcnt}, 20, "one should be able to override maxcnt";
		$itt = App::MtAws::QueueJob::Iterator->new(iterator => sub {});
		is $itt->{maxcnt}, 30, "default maxcnt should be 30";
	}


	my $maxcnt = 7;
	lcg_srand 777654 => sub {

		alarm 180;
		for my $n (0, 1, 2, 5, $maxcnt - 1, $maxcnt, $maxcnt+1, $maxcnt*2, $maxcnt*2+1, $maxcnt*3, $maxcnt*3-1) {
			test_case_early_finish($maxcnt, $n, 1);
			test_late_finish($maxcnt, $n, 1);
		}
		alarm 0;

		for my $n (0, 1, 2, 3, 4, 5) {
			# this already protected by alarm
			test_random_finish($maxcnt, $n, 1, $_) for (1..$n+1);
			test_random_finish($maxcnt, $n, 2, $n+1);
			test_random_finish($maxcnt, $n, 3, $n+1);
		}
	};
};

1;
