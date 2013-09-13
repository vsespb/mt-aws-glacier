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
use Test::More tests => 53;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::QueueJobResult;
use TestUtils;

warning_fatal();

my @codes = (JOB_RETRY, JOB_OK, JOB_WAIT, JOB_DONE);
my $coderef = sub { };

# partial_new, partial_full

cmp_deeply (App::MtAws::QueueJobResult->partial_new(a => 1, b => 2), bless { _type => 'partial', a => 1, b => 2 }, 'App::MtAws::QueueJobResult');
cmp_deeply (App::MtAws::QueueJobResult->full_new(a => 1, b => 2), bless { _type => 'full', a => 1, b => 2 }, 'App::MtAws::QueueJobResult');


# state

cmp_deeply (App::MtAws::QueueJobResult->partial_new(state => 'abc'), state('abc'));


# task
{
	cmp_deeply (App::MtAws::QueueJobResult->partial_new(task_action => 'abc', task_cb => $coderef, code => JOB_OK, task_args => []), task('abc', $coderef));
	cmp_deeply (App::MtAws::QueueJobResult->partial_new(task_action => 'abc', task_cb => $coderef, code => JOB_OK, task_args => [1, 'z']), task('abc', 1, 'z', $coderef));

	ok ! eval { task($coderef); 1; }, "should complain without task_action";
	like $@, qr/no task action/, "should complain without task_action";

	ok ! eval { task('a', 'b'); 1; }, "should complain without coderef";
	like $@, qr/no code ref/, "should complain without task_action";
};


# codes

{
	for (@codes) {
		like $_, qr/^MT_J_/;
		ok $_, "code should be true";
		ok App::MtAws::QueueJobResult::is_code($_);
		ok !App::MtAws::QueueJobResult::is_code("someprefix$_");
	}

	{
		my %h = map { $_ => 1 } @codes;
		is scalar keys %h, scalar @codes, "there should be no string duplicates";
	}
}

# parse_result

{
	ok ! eval { parse_result(); 1 };
	like $@, qr/no data/;

	ok ! eval { parse_result(1); 1 };
	like $@, qr/bad code/;

	ok ! eval { parse_result({}); 1 };
	ok ! eval { parse_result(sub {}); 1 };

	ok ! eval { parse_result(App::MtAws::QueueJobResult->full_new); 1 };
	like $@, qr/should be partial/;

	ok ! eval { parse_result(JOB_OK); 1 };
	like $@, qr/no action/, "should not allow sole JOB_OK ";

	for my $c (@codes) {
		ok ! eval { parse_result($c, task("mytask", sub {})); 1 };
		like $@, qr/double code/, "should not allow cobmining code and task for code $c";
	}

	cmp_deeply(App::MtAws::QueueJobResult->full_new(code => JOB_OK, task_action => "mytask", task_args => [], task_cb => $coderef ),
		parse_result(task("mytask", $coderef)), "should allow task");

	cmp_deeply(App::MtAws::QueueJobResult->full_new(code => JOB_OK, task_action => "mytask", task_args => [], task_cb => $coderef, state => "somestate" ),
		parse_result(task("mytask", $coderef), state("somestate")), "should allow task+state");

	for my $c (grep { $_ ne JOB_OK } @codes) {
		cmp_deeply( App::MtAws::QueueJobResult->full_new(code => $c), parse_result($c), "should allow sole code $c" );
		cmp_deeply( App::MtAws::QueueJobResult->full_new(code => $c, state => "somestate"), parse_result($c, state("somestate")), "should allow code $c and state" );
	}
	cmp_deeply( App::MtAws::QueueJobResult->full_new(code => JOB_RETRY, state => "somestate"), parse_result(state("somestate")), "should allow sole state" );

}


1;
