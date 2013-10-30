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
use Test::More tests => 24;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::QueueJob;
use App::MtAws::QueueJobResult;
use TestUtils;

use Data::Dumper;

warning_fatal();

sub expect_code
{
	my ($j, $code) = @_;
	my $res = $j->next;
	is $res->{code}, $code;
	$res;
}

sub expect_task
{
	my ($j, $task_action) = @_;
	my $res = $j->next;
	is $res->{task}{action}, $task_action;
	$res;
}

{
	{
		package JobRetryStates;
		use App::MtAws::QueueJobResult;
		use base 'App::MtAws::QueueJob';
		sub init { shift->enter('s1') };
		sub on_s1 { state 's2' };
		sub on_s2 { state 's3' };
		sub on_s3 { state 'done' };
	}
	my $j = JobRetryStates->new();
	expect_code $j,JOB_DONE;
}


{
	package JobWaitStates;
	use App::MtAws::QueueJobResult;
	use base 'App::MtAws::QueueJob';
	sub init { shift->enter('s1') };
	sub on_s1 { task('t1', sub{}), state 's2' };
	sub on_s2 { task('t2', sub{}), state 's3' };
	sub on_s3 { shift->{secret} = 'sezam'; JOB_WAIT, state 'done' };
}

sub job_wait_states_test
{
	my ($j) = @_;
	expect_task $j, 't1';
	expect_task $j, 't2';
	expect_code $j,JOB_WAIT;

}

{
	my $j = JobWaitStates->new();
	job_wait_states_test($j);
	expect_code $j,JOB_DONE;
}

{
	package JobNested;
	use App::MtAws::QueueJobResult;
	use base 'App::MtAws::QueueJob';
	sub init { shift->enter('sa') };
	sub on_sa { task('tx', sub{}), state 'sb' };
	sub on_sb { my $self = shift; state 'wait', job(JobWaitStates->new(), sub { $self->{secret} = shift->{secret}; state 'sc' }) };
	sub on_sc { my $self = shift; task("ty_$self->{secret}", sub{}), state 'sd' };
	sub on_sd { JOB_DONE };
}

sub job_nested_tests
{
	my ($j) = @_;
	expect_task $j, 'tx';
	job_wait_states_test($j);
	expect_task $j, 'ty_sezam';
}

{
	my $j = JobNested->new();
	job_nested_tests($j);
	expect_code $j,JOB_DONE;
}

{
	package JobDoubleNested;
	use App::MtAws::QueueJobResult;
	use base 'App::MtAws::QueueJob';
	sub init{};
	sub on_default { task('abc', sub{}), state 's2' };
	sub on_s2 { state 's3', job(JobNested->new()) };
	sub on_s3 { task('def', sub{}), state 'sd' };
	sub on_sd { JOB_DONE };
}

sub job_double_nested_tests
{
	my ($j) = @_;
	expect_task $j, 'abc';
	job_nested_tests($j);
	expect_task $j, 'def';
}

{
	my $j = JobDoubleNested->new();
	job_double_nested_tests($j);
	expect_code $j,JOB_DONE;
}


{
	package JobCallbackStates;
	use Carp;
	use App::MtAws::QueueJobResult;
	use base 'App::MtAws::QueueJob';
	sub init { shift->enter('s1') };
	sub on_s1 {
		my ($self) = @_;
		state 'wait', task('t1', sub{
			my ($args, $attachment) = @_;
			$self->{param} = $args->{param} || confess;
			$self->{attachment} = $attachment || confess;
			state 'done';
		});
	};
}

sub job_callback_states_test
{
	my ($j) = @_;
	cmp_deeply [expect_task($j, 't1')->{task}{cb_task_proxy}->({param => 42}, \"somescalar")], [], "cb_task_proxy should return empty list";
}

{
	my $j = JobCallbackStates->new();
	job_callback_states_test($j);
	expect_code $j,JOB_DONE;
	is $j->{param}, 42;
	is ${$j->{attachment}}, "somescalar";
}


1;
