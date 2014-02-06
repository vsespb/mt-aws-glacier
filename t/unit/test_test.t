#!/usr/bin/env perl

# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2014  Victor Efimov
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
use Test::More tests => 31;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';



# Tests of test libraries

#
# test_fask_ok/fask_ok
#

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq 'my test failed!', "fast_ok should work when failed";
	};
	test_fast_ok 11, "my test" => sub {
		fast_ok(1) for (1..10);
		fast_ok 0, "my test failed!";
	};
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq 'my test - FAILED', "fast_ok should work when failed without message";
	};
	test_fast_ok 11, "my test" => sub {
		fast_ok(1) for (1..10);
		fast_ok 0;
	};
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq 'my test failed 123 !', "fast_ok should work when message is a closure";
	};
	test_fast_ok 11, "my test" => sub {
		fast_ok(1) for (1..10);
		my $z = 123;
		fast_ok 0, sub { "my test failed $z !" };
	};
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq 'my test failed!', "fast_ok should not continue execution";
	};
	test_fast_ok 1, "my test" => sub {
		fast_ok 0, "my test failed!";
		ok 0, "should not continue execution"
	};
}

{
	no warnings 'redefine';
	ok ! eval {
		test_fast_ok 1, "my test" => sub {
			fast_ok 1, "my test failed!";
			die { x => 42}
		};
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
	test_fast_ok 11, "my test" => sub {
		fast_ok(1) for (1..10);
		fast_ok 1, "my test failed!";
	};
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq "my test - expected 12 tests, but ran 10", "fast_ok should fail when run too few tests";
	};
	test_fast_ok 12, "my test" => sub {
		fast_ok(1) for (1..10);
	};
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok !$r && $msg eq "my test - expected 12 tests, but ran 14", "fast_ok should fail when run too many tests";
	};
	test_fast_ok 12, "my test" => sub {
		fast_ok(1) for (1..14);
	};
}

{
	no warnings 'redefine';
	local *TestUtils::ok = sub {
		my ($r, $msg) = @_;
		ok $r, "should allow nesting of fast_ok";
	};
	test_fast_ok 12, "my test" => sub {
		fast_ok(1) for (1..12);
		test_fast_ok 7, "my test 2" => sub {
			fast_ok(1) for (1..7);
		};
		test_fast_ok 3, "my test 2" => sub {
			fast_ok(1) for (1..3);
		}
	};
}

#
# capture_stdout/capture_stdout
#

{
	my $res = capture_stdout my $out, sub {
		print "Test123\nTest456";
		42;
	};
	is $res, 42;
	is $out, "Test123\nTest456", "should work with stdout when out is undefined";
}

{
	my $out = '';
	my $res = capture_stdout $out => sub {
		print "Test123\nTest456";
		42;
	};
	is $res, 42;
	is $out, "Test123\nTest456", "should work with stdout when out defined";
}

{
	my $res = capture_stderr my $out, sub {
		print STDERR "Test123\nTest456";
		42;
	};
	is $res, 42;
	is $out, "Test123\nTest456", "should work with stderr when out is undefined";
}

{
	my $out = '';
	my $res = capture_stderr $out => sub {
		print STDERR "Test123\nTest456";
		42;
	};
	is $res, 42;
	is $out, "Test123\nTest456", , "should work with stdout when out is defined";
}


{ # test is_iv_without_pv
	ok is_iv_without_pv(1);
	ok !is_iv_without_pv("1");
	my $x = 1;
	ok is_iv_without_pv($x);
	my $z = "$x";
	ok !is_iv_without_pv($x);

	my $y = "2";
	$y = $y + 0;
	ok !is_iv_without_pv($y);
}

# is_posix_root

{
	if ($^O eq 'cygwin') {
		require Win32;
		ok ( (!! is_posix_root()) == (!!Win32::IsAdminUser()) );
		ok ( (!! is_posix_root()) == (!!Win32::IsAdminUser()) ); # double check, as it's cached
	} else {
		ok ( (!! is_posix_root()) == (!! ($>==0)) );
		ok ( (!! is_posix_root()) == (!! ($>==0)) ); # double check, as it's cached
	}

}

{
	use JSON::XS 1;
	
	my $json = JSON::XS->new->utf8->allow_nonref;
	
	my $s = $json->encode({myfield => JSON_XS_TRUE});
	like $s, qr/\:\s*true\s*\}/;
	ok $json->decode($s)->{myfield};
	
	$s = $json->encode({myfield => JSON_XS_FALSE});
	like $s, qr/\:\s*false\s*\}/;
	ok !$json->decode($s)->{myfield};
}

1;
