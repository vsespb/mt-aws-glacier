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
use Test::More tests => 206;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use TestUtils;

warning_fatal();

my @codes = (JOB_RETRY, JOB_OK, JOB_WAIT, JOB_DONE);
my $coderef = sub { "dummy" };

# partial_new, partial_full

cmp_deeply (App::MtAws::QueueJobResult->partial_new(a => 1, b => 2), bless { _type => 'partial', a => 1, b => 2 }, 'App::MtAws::QueueJobResult');
cmp_deeply (App::MtAws::QueueJobResult->full_new(a => 1, b => 2), bless { _type => 'full', a => 1, b => 2 }, 'App::MtAws::QueueJobResult');

{
	my ($r1, $r2) = map { { map { $_ => 1 } @$_ } } \@App::MtAws::QueueJobResult::valid_fields, [qw/code default_code task state job/];
	cmp_deeply $r1, $r2, "valid_fields should contain right data",
}

# state
cmp_deeply ([App::MtAws::QueueJobResult->partial_new(state => 'abc'), App::MtAws::QueueJobResult->partial_new(default_code => JOB_RETRY)],
	[state('abc')]);

# job
cmp_deeply ([JOB_RETRY, App::MtAws::QueueJobResult->partial_new(job => { job => 'abc'})], [job('abc')]);
cmp_deeply ([JOB_RETRY, App::MtAws::QueueJobResult->partial_new(job => { job => 'abc', cb => $coderef })], [job('abc', $coderef)]);


# task
{
	cmp_deeply
		[task('abc', $coderef)],
			[JOB_OK, App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef, args => {}})];
	cmp_deeply
		[task('abc', { z => 1}, $coderef)],
			[JOB_OK, App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef, args => {z => 1}})];

	my $attachment = "somedata";
	cmp_deeply [task('abc', { z => 1}, \$attachment, $coderef)],
		[JOB_OK, App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef, args => {z => 1}, attachment => \$attachment})];

	ok ! eval { my @a = task("something"); 1; }, "should complain with 1 arg";
	like $@, qr/^at least two args/, "should complain without task_action";

	ok ! eval { my @a = task('a', 'z'); 1; }, "should complain if second arg is not hashref";
	like $@, qr/^no code ref/, "should complain if second arg is not hashref";

	ok ! eval { my @a = task('a', 'z', $coderef); 1; }, "should complain if second arg is not hashref";
	like $@, qr/^task_args should be hashref/, "should complain if second arg is not hashref";

	ok ! eval { my @a = task('a', {z => 1 }); 1; }, "should complain without coderef";
	like $@, qr/^no code ref/, "should complain without coderef";

	ok ! eval { my @a = task('a', {z => 1 }, "scalar", $coderef); 1; }, "should complain if attachment is not reference";
	like $@, qr/^attachment is not reference to scalar/, "should complain if attachment is not reference";

	# task can be constructed from another task object
	{
		my $coderef2 = sub { "dummy2" };
		cmp_deeply
			[task(parse_result(task('abc', $coderef))->{task}, $coderef2)],
			[JOB_OK, App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef2, args => {}})];
		cmp_deeply
			[task(parse_result(task('abc', {a => 3}, $coderef))->{task}, $coderef2)],
			[JOB_OK, App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef2, args => {a => 3}})];
		my $attachment = \"somedata";
		cmp_deeply
			[task(parse_result(task('abc', {a => 3}, $attachment, $coderef))->{task}, $coderef2)],
			[JOB_OK, App::MtAws::QueueJobResult->partial_new(task => {action => 'abc', cb => $coderef2, args => {a => 3}, attachment => $attachment})];
	}
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
	like $@, qr/^no data/;

	ok ! eval { parse_result(1); 1 };
	like $@, qr/^bad code/;

	ok ! eval { parse_result({}); 1 };
	ok ! eval { parse_result(sub {}); 1 };

	ok ! eval { parse_result(App::MtAws::QueueJobResult->full_new); 1 };
	like $@, qr/^should be partial/;

	ok ! eval { parse_result(JOB_OK); 1 };
	like $@, qr/^no task/, "should not allow sole JOB_OK ";

	for my $c (@codes) {
		ok ! eval { parse_result($c, task("mytask", sub {})); 1 };
		like $@, qr/^code already/, "should not allow cobmining code and task for code $c";
	}

	for my $field (@App::MtAws::QueueJobResult::valid_fields) {
		my $a1 = App::MtAws::QueueJobResult->partial_new($field => "somevalue1");
		my $a2 = App::MtAws::QueueJobResult->partial_new($field => "somevalue2");
		ok !eval { parse_result($a1, $a2); 1; };
		like $@, qr/^double data/, "should not allow double data";
	}


	# code and default_code
	cmp_deeply parse_result(
		App::MtAws::QueueJobResult->partial_new(default_code => JOB_WAIT),
		JOB_RETRY
	), App::MtAws::QueueJobResult->full_new(code => JOB_RETRY), "existing code should not be overwritten by default_code";

	cmp_deeply parse_result(
		App::MtAws::QueueJobResult->partial_new(default_code => JOB_WAIT),
	), App::MtAws::QueueJobResult->full_new(code => JOB_WAIT), "code should default to default_code";

	# task
	cmp_deeply(parse_result(task("mytask", $coderef)),
		App::MtAws::QueueJobResult->full_new(code => JOB_OK, task => {action => "mytask", args => {}, cb => $coderef} ), "should allow task");

	# task+state
	cmp_deeply(parse_result(task("mytask", $coderef), state("somestate")),
		App::MtAws::QueueJobResult->full_new(code => JOB_OK, task => {action => "mytask", args => {}, cb => $coderef}, state => "somestate" ), "should allow task+state");

	# code+state
	for my $c (grep { $_ ne JOB_OK } @codes) {
		cmp_deeply( parse_result($c), App::MtAws::QueueJobResult->full_new(code => $c), "should allow sole code $c" );
		cmp_deeply( parse_result($c, state("somestate")), App::MtAws::QueueJobResult->full_new(code => $c, state => "somestate"), "should allow code $c and state" );
	}
	cmp_deeply( parse_result(state("somestate")), App::MtAws::QueueJobResult->full_new(code => JOB_RETRY, state => "somestate"), "should allow sole state" );

}

# another way to test compatibility between parse_result arguments
{
	for my $code ([], map { [$_] } @codes) {
		for my $job ([], [job('abc')]) {
			for my $task ([], [ task("def", sub {}) ]) {
				for my $state ([], [state("xyz")]) {
					for my $code_value (@$code ? ($code, [App::MtAws::QueueJobResult->partial_new(code => $code->[0])]) : ()) {

						my $got = eval { parse_result(@$code_value, @$job, @$task, @$state); };
						my $expected = undef;


						# cases when incompatible
						$expected = 0 unless (@$code || @$job || @$task || @$state);

						$expected = 0 if (@$task && @$code);
						$expected = 0 if (@$job && @$code);
						$expected = 0 if (@$job && @$task);
						$expected = 0 if (@$code && !@$task && $code->[0] eq JOB_OK);

						# cases when compatible
						$expected = 1 if (@$state && !@$code && !@$task && !@$job);

						$expected = 1 if (@$task && !@$code && !@$job);
						$expected = 1 if (@$job  && !@$code && !@$task);
						$expected = 1 if (@$code && $code->[0] ne JOB_OK && !@$job && !@$task );

						ok defined $expected;

						if ($expected) {
							ok $got;
						} else {
							ok !defined($got);
						}
					}
				}
			}
		}
	}
}


1;
