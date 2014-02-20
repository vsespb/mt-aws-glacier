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
use Test::More tests => 94;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';

#TODO: rewrite using core Time::Piece ? https://github.com/azumakuniyuki/perl-benchmark-collection/blob/master/module/datetime-vs-time-piece.pl
use App::MtAws::DateTime;


use App::MtAws::Utils;
use Carp;

use Digest::SHA qw/sha256_hex/;
use DateTime;



# test iso8601_to_epoch
{
	for (
		['20121225T100000Z', 1356429600],
		['20130101T000000Z', 1356998400],
		['20120229T000000Z', 1330473600],
		['20130228T000000Z', 1362009600],
		['20130228T235959Z', 1362095999],
		['20120630T235959Z', 1341100799], # leap second
		['20120701T000000Z', 1341100800], # after leap second
		['20081231T235959Z', 1230767999], # before leap second
		#['20081231T235960Z', 1230768000], # leap second is broken
		['20090101T000000Z', 1230768000], # after leap second
		['19070809T082454Z', -1969112106], # negative value
		['19070809T084134Z', -1969111106], # negative value
		['19700101T000000Z', 0],
	) {
		my $result = iso8601_to_epoch($_->[0]);
		ok($result == $_->[1], 'should parse iso8601');

		my $dt = DateTime->from_epoch( epoch => $_->[1] );
		my $dt_8601 = sprintf("%04d%02d%02dT%02d%02d%02dZ", $dt->year, $dt->month, $dt->day, $dt->hour, $dt->min, $dt->sec);
		ok( $_->[0] eq $dt_8601, "iso8601 $dt_8601 should be correct string");
	}
}

# test different formats iso8601_to_epoch
{
	for (
		['20121225T100000Z', 1356429600],
		['20130101t000000Z', 1356998400],
		['20120229 T 000000Z', 1330473600],
		['2013-02-28T00:00:00Z', 1362009600],
		['20130228 t 235959z', 1362095999],
		['20120630T23:59:59  Z', 1341100799], # leap second
		['  20120701 T 000000 Z', 1341100800], # after leap second
		['2008 12 31 T 23 59 59Z', 1230767999], # before leap second
		['2009 01-01T 00:00 00 z', 1230768000], # after leap second
		['2009 01-01T 00:00 00.123 z', 1230768000],
		['2009 01-01T 00:00 00,1234 z', 1230768000],
		# more examples with leap second
		['1998-12-31T23:59:60Z', 915148800],
		['1999-01-01T00:00:00Z', 915148800],
		['1998-12-31T23:59:59Z', 915148799],
		['1998-12-31T23:59:60Z', 915148800],
	) {
		my $result = iso8601_to_epoch($_->[0]);
		ok($result == $_->[1], "should parse iso8601 $result == $_->[1]");
	}
}

for ("2014\x850101T000055Z") {
	ok(!defined iso8601_to_epoch($_), "should not treat \x85 as space separator");
	utf8::upgrade($_);
	ok(!defined iso8601_to_epoch($_), "should not treat \x85 as space separator in upgraded string");
	ok utf8::is_utf8($_), "should not downgrade source string";
}


# check time converts both ways

is iso8601_to_epoch("16800101T000000Z"), -9151488000;
is iso8601_to_epoch("22600101T000000Z"), 9151488000;
is iso8601_to_epoch("40000201T000000Z"), 64063267200;
is iso8601_to_epoch("19691231T235950Z"), -10;
is iso8601_to_epoch("20140114T003509Z"), 1389659709;

is iso8601_to_epoch("20371231T235959Z"), 2145916799;
is iso8601_to_epoch("20380101T000000Z"), 2145916800;
is iso8601_to_epoch("19011231T235959Z"), -2145916801;
is iso8601_to_epoch("19020101T000000Z"), -2145916800;

ok defined iso8601_to_epoch(sprintf("2014%02d01T000000Z", $_)) for (1..12);
ok defined iso8601_to_epoch(sprintf("201401%02dT000000Z", $_)) for (1,2,30,31);
ok defined iso8601_to_epoch(sprintf("20140101T%02d0000Z", $_)) for (0,1,22,23);
ok defined iso8601_to_epoch(sprintf("20140101T00%02d00Z", $_)) for (0,1,58,59);
ok defined iso8601_to_epoch(sprintf("20140101T0000%02dZ", $_)) for (0,1,58,59);

ok !defined iso8601_to_epoch("20141301T000000Z");
ok !defined iso8601_to_epoch("20140132T000000Z");
ok !defined iso8601_to_epoch("20140101T240000Z");
ok !defined iso8601_to_epoch("20140101T006000Z");
ok !defined iso8601_to_epoch("20140101T000063Z");


ok !defined iso8601_to_epoch("09990101T000000Z"), "should disallow years before 1000";
ok defined epoch_to_iso8601(253402300799);
ok !defined epoch_to_iso8601(253402300799+1), "should disallow years after 9999";

# test correctness and consistency of iso8601_to_epoch and epoch_to_iso8601
{
	my @a;
	for my $year (1000..1100, 1800..1850, 1890..1910, 1970..2040, 2090..2106,
		(map { $_* 100-2, $_* 100-1, $_* 100, $_*100+1, $_*100+2 } 25..99), 9901..9999)
	{
		for my $month (1,2,3,12) {
			for my $day (
				1..2, 28,
				($month == 2 && ( ($year % 100 == 0) ? ($year % 400 == 0) : ($year % 4 == 0)  ) ) ? (29) : (),
				($month == 12 || $month == 1) ? (30, 31) : ()
			) {
				for my $time ("000000", "235959") {
					my $str = sprintf("%04d%02d%02dT%sZ", $year, $month, $day, $time);
					my $r = iso8601_to_epoch($str);
					if (is_64bit_time) {
						my $str_a = epoch_to_iso8601($r); # reverse
						die "$str, $r" unless defined $str_a;
						die "$str_a $str" unless $str_a eq $str;
					}
					die $r unless $r =~ /^\-?\d+$/; # numbers only, no floating point
					push @a, $r;
				}
			}
		}
	}
	is sha256_hex(join(",", @a)), '49c852f65d2d9ceeccdc02f64214f1a2d249d00337bf669288c34a603ff7acbf', "hardcoded checksum";
}

# test if filesystem/OS supports particular time range, epoch_to_iso8601 supports it too.
{
	my $mtroot = get_temp_dir();
	my $filename = "$mtroot/f1";
	open my $f, ">", $filename or confess;
	close $f or confess;
	for (
		["16800101T000000Z", -9151488000],
		["22600101T000000Z", 9151488000],
		["40000201T000000Z", 64063267200],
	) {
		my ($strtime, $numtime) = ($_->[0], $_->[1]);
		eval { utime time(), $numtime, $filename; };
		my $got = eval { file_mtime($filename); };
		SKIP: {
			skip "unable to set file mtime=$numtime", 1 unless $got == $numtime;
			is epoch_to_iso8601($got), $strtime;
		}
	}
	unlink $filename;
}

# list vs scalar context

{
	my $date = '20121225T100000Z';
	my $result = iso8601_to_epoch($date);
	my @a = iso8601_to_epoch($date);
	is $a[0], $result, "should work same way in list context";
}

# test error handling iso8601_to_epoch
{
	for (qw/20121515T100000Z 1234/) {
		ok ! defined iso8601_to_epoch($_);
	}
}


1;
