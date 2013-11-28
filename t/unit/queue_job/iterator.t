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
use Test::More tests => 857;
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
		state 'wait', task("abc$_[0]->{n}", {x => $_[0]->{n}}, sub {
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


sub create_iterator
{
	my ($maxcnt, $cnt) = @_;
	my @orig_parts = map { SimpleJob->new(n => $_) } (1..$cnt);
	App::MtAws::QueueJob::Iterator->new(maxcnt => $maxcnt, iterator => sub { @orig_parts ? shift @orig_parts : () });
}

sub test_case_early_finish
{
	my ($maxcnt, $cnt) = @_;

	my $itt = create_iterator($maxcnt, $cnt);
	my @actions;
	while (1) {
		my $r = $itt->next;
		ok $r->{code} eq JOB_OK || $r->{code} eq JOB_DONE;
		last if $r->{code} eq JOB_DONE;
		push @actions, $r->{task}{action};
		$r->{task}{cb_task_proxy}->("somedata1");
	}

	cmp_deeply [sort @actions], [sort map { "abc$_" } 1..$cnt], "test it works when callback called immediately";

}

sub test_late_finish
{
	my ($maxcnt, $cnt) = @_;
	my $itt = create_iterator($maxcnt, $cnt);

	my @actions = ();
	my @passes;
	while (@actions < $cnt) {
		my @callbacks = ();
		my $r;
		while (1) {
			$r = $itt->next;
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
	cmp_deeply [sort @actions], [sort map { "abc$_" } 1..$cnt];
	is pop @passes, $cnt % $maxcnt, "last pass should contain cnt mod maxcnt items" if ($cnt % $maxcnt);
	is $_, $maxcnt, "all passes excapt last should contain maxcnt items (if more than one pass)" for (@passes);
	is $itt->next->{code}, JOB_DONE, "test it works when callback called later";
}

sub test_random_finish
{
	my ($maxcnt, $cnt, $nworkers) = @_;
	my $itt = create_iterator($maxcnt, $cnt);
	my $q = QE->new(n => $nworkers);
	$q->process($itt);

	for (@{ $q->{res} }) {
		ok $_->{action} =~ /^abc(\d+)/;
		cmp_deeply $_->{data}, [x => $1];
	}
	cmp_deeply [sort map { $_->{action} } @{ $q->{res} }], [sort map { "abc$_" } 1..$cnt];
}

my $maxcnt = 7;
lcg_srand 777654 => sub {
	for my $n (1, 2, 5, $maxcnt - 1, $maxcnt, $maxcnt+1, 20) {
		test_case_early_finish($maxcnt, $n);
		test_late_finish($maxcnt, $n);
		test_random_finish($maxcnt, $n, $_) for (1, 2, 3, 4);
		if ($n > 4) {
			test_random_finish($maxcnt, $n, $n - 1);
			test_random_finish($maxcnt, $n, $n);
			test_random_finish($maxcnt, $n, $n + 1);
		}
	}
};

# TODO: test that on_itt_and_jobs won't eat up all memory

1;
