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
use Test::More tests => 90;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use TestUtils;
use LCGRandom;
use MyQueueEngine;

use Data::Dumper;

warning_fatal();

{
	{
		package QE;

		use strict;
		use warnings;
		use base q{MyQueueEngine};

		sub on_task_a
		{
			my ($self, %args) = @_;
			{ xx1 => "a=$args{a},b=$args{b},c=$args{c}", xx2 => "thexx2" };
		}

		sub on_task_b
		{
			my ($self, %args) = @_;
			{ yy1 => 'z', yy2 => 'f' };
		}

		sub on_task_c
		{
			my ($self, %args) = @_;
			{ zz1 => "thezz1", zz2 => "Y1=($args{y1}); Y2=($args{y2})" };
		}
	};

	{
		package MultiJob;

		use strict;
		use warnings;
		use Carp;
		use App::MtAws::QueueJobResult;
		use base q{App::MtAws::QueueJob};

		our $_destroy_count = 0;

		sub init
		{
			my ($self) = @_;
			$self->{a}||confess;
			$self->{b}||confess;
			$self->{c}||confess;
			$self->{cnt}||confess;
			$self->enter("s1");
			return $self;
		}

		sub on_s1
		{
			my ($self) = @_;
			return
				state("wait"),
				job( JobA->new(map { $_ => $self->{$_} } qw/a b c/), sub {
					my $j = shift;
					$self->{$_} = $j->{$_} or confess for qw/x1 x2/;
					state("s2")
				});
		}

		sub on_s2
		{
			my ($self) = @_;
			return
				state("wait"),
				job( JobB->new(map { $_ => $self->{$_} } qw/cnt a b c x1 x2/), sub {
					my $j = shift;
					$self->{$_} = $j->{$_} or confess for qw/y1 y2/;
					state("s3")
				});
		}

		sub on_s3
		{
			my ($self) = @_;
			return
				state("wait"),
				job( JobC->new(map { $_ => $self->{$_} } qw/a b c y1 y2/), sub {
					my $j = shift;
					$self->{$_} = $j->{$_} or confess for qw/z1 z2/;
					state("done")
				});
		}

		sub DESTROY
		{
			$_destroy_count++;
		}
	};

	{
		package JobA;


		use strict;
		use warnings;
		use App::MtAws::QueueJobResult;
		use base q{App::MtAws::QueueJob};
		use Carp;

		our $_destroy_count = 0;

		sub init{};
		sub on_default
		{
			my ($self) = @_;
			return state "wait", task "task_a", { map { $_ => $self->{$_} } qw/a b c/ } => sub {
				my ($args) = @_;
				$self->{x1} = $args->{xx1} or confess;
				$self->{x2} = $args->{xx2} or confess;
				state("done")
			}
		}

		sub DESTROY
		{
			$_destroy_count++;
		}
	};

	{
		package JobB;

		use strict;
		use warnings;
		use App::MtAws::QueueJobResult;
		use base q{App::MtAws::QueueJob};
		use Carp;

		our $_destroy_count = 0;

		sub init
		{
			my ($self) = @_;
			$self->{cnt}||confess;
			$self->{t} = {};
			$self->{y1} = "y1:";
			$self->{y2} = "y2:";
		}

		sub on_default
		{
			my ($self) = @_;

			if ((my $i = $self->{cnt}--) > 0) {
				$self->{t}{$i} = 1;
				return task 'task_b', {  map { $_ => $self->{$_} } qw/a b c x1 x2/  } => sub {
					my ($args) = @_;
					$self->{y1} .= $args->{yy1};
					$self->{y2} .= $args->{yy2};
					delete $self->{t}->{$i} or confess;
					return;
				}
			} else {
				if (keys %{$self->{t}}) {
					return JOB_WAIT;
				} else {
					return state('done');
				}
			}
		}

		sub DESTROY
		{
			$_destroy_count++;
		}
	};

	{
		package JobC;

		use strict;
		use warnings;
		use App::MtAws::QueueJobResult;
		use base q{App::MtAws::QueueJob};
		use Carp;

		our $_destroy_count = 0;

		sub init{};

		sub on_default
		{
			my ($self) = @_;
			return state "wait", task "task_c", { map { $_ => $self->{$_} } qw/a b c y1 y2/ } => sub {
				my ($args) = @_;
				$self->{z1} = $args->{zz1} or confess;
				$self->{z2} = $args->{zz2} or confess;
				state("done")
			}
		}

		sub DESTROY
		{
			$_destroy_count++;
		}
	}

	lcg_srand 4672 => sub {
		for my $n (1, 10, 100) {
			for my $workers (1, 2, 10) {
				my $destroy_count;
				$MultiJob::_destroy_count = $JobA::_destroy_count = $JobB::_destroy_count = $JobC::_destroy_count = 0;

				{
					my $j = MultiJob->new(cnt => $n, a => 101, b => 102, c => 103);
					my $q = QE->new(n => $workers);
					$q->process($j);

					my $x1 = "a=101,b=102,c=103";
					my $x2 = "thexx2";
					my $y1 = "y1:".("z"x$n);
					my $y2 = "y2:".("f"x$n);
					my $z1 = "thezz1";
					my $z2 = "Y1=($y1); Y2=($y2)";

					is $j->{x1}, $x1;
					is $j->{x2}, $x2;
					is $j->{y1}, $y1;
					is $j->{y2}, $y2;
					is $j->{z1}, $z1;
					is $j->{z2}, $z2;
				}
				is $MultiJob::_destroy_count, 1;
				is $JobA::_destroy_count, 1;
				is $JobB::_destroy_count, 1;
				is $JobC::_destroy_count, 1;
			}
		}
	}
}
1;
