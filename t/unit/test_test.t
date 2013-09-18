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
use utf8;
use Test::More tests => 38;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../lib", "$FindBin::RealBin/../../lib";
use TestUtils;

warning_fatal();

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
	use LCGRandom;
	use Digest::SHA qw/sha256_hex/;
	use Test::Deep;

	# make sure we have same number sequence each time
	is sha256_hex(join(',', map { lcg_rand() } (1..10_000))), '135cbcb5641b2e7d387b083a3aa25de8e6066f28d5fe84e569dbba4ab94b1b86';
	lcg_srand(0);
	is sha256_hex(join(',', map { lcg_rand() } (1..10_000))), '135cbcb5641b2e7d387b083a3aa25de8e6066f28d5fe84e569dbba4ab94b1b86';
	lcg_srand(764846290);
	is sha256_hex(join(',', map { lcg_rand() } (1..10_000))), '8fc1c7490ccbc9fc34c484bdd94d18e3c7a43c80c8a82892127f71ce25e7d552';

	# make sure it's lcg
	lcg_srand(0);
	cmp_deeply [ map { lcg_rand } 1..10 ], [12345,1406932606,654583775,1449466924,229283573,1109335178,1051550459,1293799192,794471793,551188310];

	lcg_srand(0);
	my @a = map { lcg_rand } 1..10;
	lcg_srand();
	my @b = map { lcg_rand } 1..10;
	cmp_deeply [@b], [@a], "lcg_srand without argument works like with 0";


	for my $seed (0, 101, 105){
		lcg_srand($seed);
		my @a = map { lcg_rand } 1..10;
		lcg_srand($seed);
		my @a1 = map { lcg_rand } 1..5;
		my @bb;
		lcg_srand $seed, sub {
			@bb = map { lcg_rand } 1..10;
		};
		my @a2 = map { lcg_rand } 1..5;
		cmp_deeply [@a1, @a2], [@a], "lcg_srand properly localize seed";
		cmp_deeply [@bb], [@a], "lcg_srand accepts callback";
	}
}

1;
