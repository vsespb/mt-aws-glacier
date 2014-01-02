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
use Test::More tests => 3;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use List::Util qw/min max/;
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Iterator;
use QueueHelpers;
use TestUtils;
use LCGRandom;

warning_fatal();


use Data::Dumper;

{
	package LongJob;
	use Carp;
	use App::MtAws::QueueJobResult;use Data::Dumper;
	use base 'App::MtAws::QueueJob';

	sub init {
		my ($self) = @_;
		$self->{cnt} = 25;
		$self->{tasks} = {};
		$self->enter('one_wait');
	};

	sub on_one_wait
	{
		my ($self) = @_;
		if (${$self->{counter_ref}}) {
			--${$self->{counter_ref}} unless $self->{flag}++;
			JOB_WAIT
		} else {
			state 'bulk'
		}
	}

	sub on_bulk
	{
		my ($self) = @_;
		if (--$self->{cnt}) {
			my $i = $self->{cnt};
			$self->{tasks}{$i} = 1;
			return task("mytask", {cnt => $self->{cnt}, job_name => $self->{job_name}}, sub {
				delete $self->{tasks}{$i};
				return;
			});
		} else {
			state 'finishing';
		}
	};

	sub on_finishing
	{
		my ($self) = @_;
		return keys %{$self->{tasks}} ? JOB_WAIT : state "done";
	}

}
{
	package QE;
	use MyQueueEngine;
	use base q{MyQueueEngine};
	use Data::Dumper;

	sub queue
	{
		my ($self, $worker_id, $task) = @_;
		push @{ $self->{results} }, $task->{args};
	}

	sub on_mytask
	{
		my ($self, %args) = @_;
		"somedata0"
	}
};


lcg_srand 16 => sub {
	for my $n (2, 3, 8) {
		for my $workers_add (0, 1, 3) {
			my $max_d = 0;
			for my $try_n (1..3) {
				my $global_counter = $n;
				my @jobs = map { LongJob->new(job_name => chr(ord('A') + $_ - 1), counter_ref => \$global_counter) } 1..$n;
				my $itt = App::MtAws::QueueJob::Iterator->new(iterator => sub { shift @jobs });
				my $q = QE->new(n => $n + $workers_add);
				$q->process($itt);
				my %data;
				for (@{ $q->{results} }) {
					$data{$_->{job_name}}++;
					my @sorted = sort { $a <=> $b } values %data;
					for (my $i = 1; $i <= $#sorted; ++$i) {
						my $d = $sorted[$i] - $sorted[$i-1];
						$max_d = $d if $d > $max_d;
					}
				}
			}
			ok $max_d <= 1;
		}
	}
};

1;
__END__
