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
use utf8;
use Test::More tests => 6;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use TestUtils;

warning_fatal();

# Tests of test libraries

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq 'my test failed!', "fast_ok should work when failed";
	}; 
	test_fast_ok sub {
		fast_ok(1) for (1..10);
		fast_ok 0, "my test failed!";
	}, "my test";
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq 'my test failed 123 !', "fast_ok should work when message is a closure";
	}; 
	test_fast_ok sub {
		fast_ok(1) for (1..10);
		my $z = 123;
		fast_ok 0, sub { "my test failed $z !" };
	}, "my test";
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq 'my test failed!', "fast_ok should not continue execution";
	}; 
	test_fast_ok sub {
		fast_ok 0, "my test failed!";
		ok 0, "should not continue execution"
	}, "my test";
}

{
	no warnings 'redefine';
	ok ! eval {
		test_fast_ok sub {
			fast_ok 1, "my test failed!";
			die { x => 42}
		}, "my test";
		1;
	}, "should propogate exceptions";
	ok $@->{x} == 42, "should propogate exceptions";
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok $r && $msg eq 'my test', "fast_ok should work when ok";
	}; 
	test_fast_ok sub {
		fast_ok(1) for (1..10);
		fast_ok 1, "my test failed!";
	}, "my test";
}

1;

