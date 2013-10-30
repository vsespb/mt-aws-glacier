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
use Test::More tests => 15;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Iterator;
use App::MtAws::QueueJob::MultipartPart;
use QueueHelpers;
use TestUtils;

warning_fatal();

use Data::Dumper;

{
	{
		package SimpleJob;
		use Carp;
		use App::MtAws::QueueJobResult;use Data::Dumper;
		use base 'App::MtAws::QueueJob';
		sub init {  };

		sub on_default
		{
			state 'wait', task("abc$_[0]->{n}", sub {
				confess unless $_[0] && $_[0] =~ /^somedata\d$/;
				state 'done'
			});
		};

	}

	my $cnt = 5;

	sub create_iterator
	{
		my @orig_parts = map { SimpleJob->new(n => $_) } (1..$cnt);
		App::MtAws::QueueJob::Iterator->new(iterator => sub { @orig_parts ? shift @orig_parts : () });
	}


	my $itt = create_iterator();
	my @actions;
	while (1) {
		my $r = $itt->next;
		ok $r->{code} eq JOB_OK || $r->{code} eq JOB_DONE;
		last if $r->{code} eq JOB_DONE;
		push @actions, $r->{task}{action};
		$r->{task}{cb_task_proxy}->("somedata1");
	}

	cmp_deeply [sort @actions], [sort map { "abc$_" } 1..$cnt], "test it works when callback called immediately";

	$itt = create_iterator();
	@actions = ();
	my @callbacks = ();
	while (1) {
		my $r = $itt->next;
		ok $r->{code} eq JOB_OK || $r->{code} eq JOB_WAIT;
		last if $r->{code} eq JOB_WAIT;
		push @actions, $r->{task}{action};
		push @callbacks, $r->{task}{cb_task_proxy};
	}
	cmp_deeply [sort @actions], [sort map { "abc$_" } 1..$cnt];

	$_->("somedata2") for @callbacks;
	is $itt->next->{code}, JOB_DONE, "test it works when callback called later";
}

1;
