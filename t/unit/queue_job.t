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
use Test::More tests => 12;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::QueueJob;
use App::MtAws::QueueJobResult;
use TestUtils;

warning_fatal();

sub expect_code
{
	my ($j, $code) = @_;
	my $res = $j->next;
	is $res->{code}, $code;
}

sub expect_task
{
	my ($j, $task_action) = @_;
	my $res = $j->next;
	is $res->{task}{action}, $task_action;
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
	{
		package JobWaitStates;
		use App::MtAws::QueueJobResult;
		use base 'App::MtAws::QueueJob';
		sub init { shift->enter('s1') };
		sub on_s1 { task('t1', sub{}), state 's2' };
		sub on_s2 { task('t2', sub{}), state 's3' };
		sub on_s3 { JOB_WAIT, state 'done' };
	}
	my $j = JobWaitStates->new();
	expect_task $j, 't1';
	expect_task $j, 't2';
	expect_code $j,JOB_WAIT;
	expect_code $j,JOB_DONE;
}

{
	{
		package JobNested;
		use App::MtAws::QueueJobResult;
		use base 'App::MtAws::QueueJob';
		sub init { shift->enter('sa') };
		sub on_sa { JOB_WAIT, state 'sb' };
		sub on_sb { state 'sc', job(JobWaitStates->new()) };
		sub on_sc { JOB_WAIT, state 'sd' };
		sub on_sd { JOB_WAIT, state 'done' };
	}
	my $j = JobNested->new();
	expect_code $j,JOB_WAIT;

	expect_task $j, 't1';
	expect_task $j, 't2';
	expect_code $j,JOB_WAIT;

	expect_code $j,JOB_WAIT;
	expect_code $j,JOB_WAIT;
	expect_code $j,JOB_DONE;
}

1;
