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
use Test::More tests => 1054;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::MetaData;
use App::MtAws::Utils;

use Test::MockModule;
use MIME::Base64 qw/encode_base64/;
use Digest::SHA qw/sha256_hex/;
use Encode;
use JSON::XS;
use Data::Dumper;
use POSIX;
use DateTime; #TODO: rewrite using core Time::Piece https://github.com/azumakuniyuki/perl-benchmark-collection/blob/master/module/datetime-vs-time-piece.pl
use Test::Spec;
use TestUtils;

warning_fatal();
use open qw/:std :utf8/; # actually, we use "UTF-8" in other places.. UTF-8 is more strict than utf8 (w/out hypen)

no warnings 'redefine';


# test _encode_b64/_decode_b64 and UTF8
{
	for (
		qq!{"c":"d","a":"b"}!,
		qq!{"c":"d",\n"a":"b"}!,
		qq!{"c":"d",\t"a":"b"}!,
		qq!andnd+asdasdf!,
		qq!andnd/asdasdf!,
		qq!andndasdasdf=!,
		qq!тест!,
		qq!тест test!,
		qq!тест=test!,
	) {
		my $result = App::MtAws::MetaData::_encode_b64(App::MtAws::MetaData::_encode_utf8($_));
		ok ($result eq _encode_base64url(encode("UTF-8", $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)), 'match base64 encode');
		ok ($result !~ /[\r\n]/m, 'does not contain linefeed');
		ok ($result !~ /[\+\/\=]/m, 'does not contain + and /');
		my $redecoded = App::MtAws::MetaData::_decode_utf8(App::MtAws::MetaData::_decode_b64($result));

		#ok(utf8::is_utf8($_), "source should be utf8 $_");
		ok(utf8::is_utf8($redecoded), "recoded should be utf8");

		ok ($redecoded eq $_, 'reverse decodable');
	}
}


# test _encode_b64 dash and underscore
{
	for (
		qq!aaa_!,
		qq!bbb-!,
		qq!aa_-!,
		qq!bb-_!,
	) {
		my $str = App::MtAws::MetaData::_decode_b64($_);
		my $rebase64 = App::MtAws::MetaData::_encode_b64($str);
		ok ($rebase64 eq $_, "use dash and underscore $_ $str");
	}
}

# test _encode_b64/_decode_b64 padding
{
	for (
		qq!a!,
		qq!bb!,
		qq!ccc!,
		qq!dddd!,
		qq!eeeee!,
		qq!ffffff!,
	) {
		my $base64url = App::MtAws::MetaData::_encode_b64($_);
		ok ($base64url !~ /=/g, "_enocde_b64 should not pad base64 $_");
		ok (App::MtAws::MetaData::_decode_b64($base64url) eq $_, "_decode_b64 should work without padding $_ $base64url");

	}
}

# test _decode_b64 should add padding
{
	for (
		qq!a!,
		qq!bb!,
		qq!ccc!,
		qq!dddd!,
		qq!eeeee!,
		qq!ffffff!,
	) {
		my $last_arg;
		my $base64 = encode_base64($_, "");
		my $base64url = App::MtAws::MetaData::_encode_b64($_);
		local *MIME::Base64::decode_base64 = sub { ($last_arg) = @_;};
		App::MtAws::MetaData::_decode_b64($base64url);
		ok ($last_arg eq $base64, "$last_arg eq $base64");
	}
}

# test _encode_b64/_decode_b64 EOL
{
	my $base64 = App::MtAws::MetaData::_encode_b64('x' x 1024);
	ok ($base64 !~ /[\r\n]/m, 'does not contain linefeed');
}



# test _encode_b64/_decode_b64 and UTF-8 with raw fixtures
{
	for (
		['{"c":"d","a":"b"}', 'eyJjIjoiZCIsImEiOiJiIn0'],
		['{"c":"d"\n,"a":"b"}', 'eyJjIjoiZCJcbiwiYSI6ImIifQ'],
		['{"c":"d",\t"a":"b"}', 'eyJjIjoiZCIsXHQiYSI6ImIifQ'],
		['andnd+asdasdf', 'YW5kbmQrYXNkYXNkZg'],
		['andnd/asdasdf', 'YW5kbmQvYXNkYXNkZg'],
		['andndasdasdf=', 'YW5kbmRhc2Rhc2RmPQ'],
		['тест', '0YLQtdGB0YI'],
		['тест test', '0YLQtdGB0YIgdGVzdA'],
		['тест=test', '0YLQtdGB0YI9dGVzdA'],
	) {
		ok (App::MtAws::MetaData::_encode_b64(App::MtAws::MetaData::_encode_utf8($_->[0])) eq $_->[1], 'base64 match fixture');
		ok (App::MtAws::MetaData::_decode_utf8(App::MtAws::MetaData::_decode_b64($_->[1])) eq $_->[0], 'fixture match base64');
	}
}



# test _encode_json/_decode_json
{
	for (
		['file', 1352924178],
		['file/a',1351924178],
		['file/a/b/c/d','1352124178'],
		['директория/a/b/c/d','1352124178'],
		['директория/файл',1352124178],
		['директория/файл',0],
		['директория/файл','0'],
	) {
		my $result = App::MtAws::MetaData::_encode_json(App::MtAws::MetaData::_encode_filename_and_mtime($_->[0], $_->[1]));
		my $recoded = JSON::XS->new->utf8->allow_nonref->decode($result);
		ok ($result !~ /[\r\n]/m, 'no linefeed');
##		ok( $result =~ /\:\s*$_->[1]/, "result should contain mtime as numeric");
		is_deeply($recoded, { mtime => to_iso8601($_->[1]), filename => $_->[0]}, "jsone string should be json with correct filename and mtime");
		my $result_decoded =decode("UTF-8", $result, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
		ok ($result_decoded =~ /\Q$_->[0]\E/m, "json string should contain UTF without escapes");

		my ($filename, $mtime) = App::MtAws::MetaData::_decode_filename_and_mtime(App::MtAws::MetaData::_decode_json($result));
		ok ($filename eq $_->[0], 'filename match');
		ok ($mtime == $_->[1], 'mtime match');
	}
}

# test meta_encode/meta_decode with fixtures
{
	for (
		['file', 1352924178, 'mt2 eyJmaWxlbmFtZSI6ImZpbGUiLCJtdGltZSI6IjIwMTIxMTE0VDIwMTYxOFoifQ'],
		['file/a',1351924178, 'mt2 eyJmaWxlbmFtZSI6ImZpbGUvYSIsIm10aW1lIjoiMjAxMjExMDNUMDYyOTM4WiJ9'],
		['file/a/b/c/d','1352124178', 'mt2 eyJmaWxlbmFtZSI6ImZpbGUvYS9iL2MvZCIsIm10aW1lIjoiMjAxMjExMDVUMTQwMjU4WiJ9'],
		['директория/a/b/c/d','1352124178', 'mt2 eyJmaWxlbmFtZSI6ItC00LjRgNC10LrRgtC-0YDQuNGPL2EvYi9jL2QiLCJtdGltZSI6IjIwMTIxMTA1VDE0MDI1OFoifQ'],
		['директория/файл',1352124178, 'mt2 eyJmaWxlbmFtZSI6ItC00LjRgNC10LrRgtC-0YDQuNGPL9GE0LDQudC7IiwibXRpbWUiOiIyMDEyMTEwNVQxNDAyNThaIn0'],
		["\xB5", 1234, 'mt2 eyJmaWxlbmFtZSI6IsK1IiwibXRpbWUiOiIxOTcwMDEwMVQwMDIwMzRaIn0'], # downgraded string
		["\xDF", 1234, 'mt2 eyJmaWxlbmFtZSI6IsOfIiwibXRpbWUiOiIxOTcwMDEwMVQwMDIwMzRaIn0'], # downgraded string
	) {
		my ($filename, $mtime) = App::MtAws::MetaData::meta_decode($_->[2]);
		ok utf8::is_utf8($filename) || $filename =~ /^[\x00-\x7f]+$/, 'check that we get back upgraded strings';
		ok $_->[0] eq $filename, "check filename";
		ok $_->[1] eq $mtime, 'check mtime';
	}
}

# test increment of length of resulting data
{
	use bytes;
	no bytes;
	my $str = '';
	my ($old_strlen, $old_encoded_lenth) = (undef, undef);
	for (qw/a b c d e f _ ß µ Ũ  а б в г д е ё ж з и к л м н о п р с т у ф ц ч ш щ э ю я А Б В Г Д Е Ё Ж З И К Л М Н О П Р С Т У Ф Х Ц Ч Ш Щ Э Ю Я/) {
		$str .= $_;
		my $strlen = bytes::length($str);
		my $encoded = App::MtAws::MetaData::meta_encode($str, 1234);
		my $encoded_length = bytes::length($encoded);

		if (defined($old_strlen) && defined($old_encoded_lenth)) {
			ok ( ($encoded_length - $old_encoded_lenth) <= int(((($strlen - $old_strlen) * 4)/3)+0.5) + 1);
		}
		$old_encoded_lenth = $encoded_length;
		$old_strlen = $strlen;
	}
}

# test increment of length of resulting data
{
	for my $str1 (qw/ ! a b c d e f _ ß µ Ũ  а б в г д е ё ж з и к л м н о п р с т у ф ц ч ш щ э ю я А Б В Г Д Е Ё Ж З И К Л М Н О П Р С Т У Ф Х Ц Ч Ш Щ Э Ю Я/) {
		for my $str2 (qw/a hello/, qq!file1/file2/file3/file4!, qq!длинный русский текст!, qq!/!) {
			my $source = $str1.$str2;
			my $encoded = App::MtAws::MetaData::meta_encode($source, 1234);
			my ($decoded, $mtime) = App::MtAws::MetaData::meta_decode($encoded);
			ok $source eq $decoded;
			ok $mtime = 1234;
		}
	}
}

sub test_undefined
{
	my ($str, $msg) = @_;
	ok !defined App::MtAws::MetaData::meta_decode($str), "$msg (scalar)";
	my @a = App::MtAws::MetaData::meta_decode($str);
	is scalar @a, 0, "$msg (array)";
}

# test error catch while decoding
{
	test_undefined 'zzz', 'should return undef if no marker present';
	test_undefined 'mt2 zzz', 'should return undef if utf is broken';
	test_undefined 'mt2 !!!!', 'should return undef if base64 is broken';
	test_undefined 'mt2 z+z', 'should return undef if base64 is broken';
	ok defined App::MtAws::MetaData::meta_decode('mt2 '._encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}').'=='), 'should allow base64 padding';
	ok defined App::MtAws::MetaData::meta_decode('mt2 '._encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}').'='), 'should allow base64 padding';
	test_undefined 'mt2 '._encode_base64url('{ "filename": "a", "mtime": "20081515T222324Z"}'), 'should return undef if mtime is broken';
	test_undefined 'mt2 '._encode_base64url('ff'), 'should return undef if json is broken';
	test_undefined 'mt2 '._encode_base64url('{ "a": 1, "x": 2}'), 'should return undef if filename and mtime missed';
	test_undefined 'mt2 '._encode_base64url('{ "filename": "f", "x": 2}'), 'should return undef if mtime missed';
	test_undefined 'mt2 '._encode_base64url('{ "x": 1, "mtime": 2}'), 'should return undef if filename missed';
	test_undefined 'mt2 '._encode_base64url('{ "filename": "a", "mtime": "zzz"}'), 'should return undef if time is broken';
	test_undefined 'mt2 '._encode_base64url('{ "filename": "'.('x' x 1024).'", "mtime": 1}'), 'should return undef if b64 too big';
	test_undefined 'mt2 '._encode_base64url('{ "filename": "f", "mtime": "20081302T222324Z"}'), 'should return undef if b64 too big';

	test_undefined '', 'should return undef, without warning, if input is empty string';
	test_undefined ' ', 'should return undef, without warning, if input is space';
	test_undefined '  ', 'should return undef, without warning, if input is multiple spaces';
	test_undefined undef, 'should return undef, without warning, if input is undef';
	ok !defined App::MtAws::MetaData::meta_decode(), 'should return undef, without warning, if input is empty list';

	for (qw/mt1 mt2/) {
		ok !defined App::MtAws::MetaData::meta_decode("$_"), 'should return undef, without warning, if input is marker plus empty string';
		ok !defined App::MtAws::MetaData::meta_decode("$_ "), 'should return undef, without warning, if input is marker plus space';
		ok !defined App::MtAws::MetaData::meta_decode("$_ "), 'should return undef, without warning, if input is marker plus multiple spaces';
	}

	ok defined App::MtAws::MetaData::meta_decode('mt2   '._encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}')), 'should allow few spaces';
	ok defined App::MtAws::MetaData::meta_decode("mt2\t\t"._encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}')), 'should allow tabs';
	ok defined App::MtAws::MetaData::meta_decode(" \tmt2\t\t "._encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}')), 'should allow leading spaces';

	eval { App::MtAws::MetaData::meta_decode('zzz') };
	ok $@ eq '', 'should not override eval code'; # it looks now that those tests are broken

	eval { App::MtAws::MetaData::meta_decode('mt2 zzz') };
	ok $@ eq '', 'should not override eval code'; # it looks now that those tests are broken




}


# test error cacth while encoding
{
	ok defined App::MtAws::MetaData::meta_encode('filename', -1), 'should not catch negative mtime';
	ok !defined App::MtAws::MetaData::meta_encode('filename', -30639629694), 'should disallow time before Y1000';
	ok !defined App::MtAws::MetaData::meta_encode('filename'), 'should catche missed mtime';
	ok !defined App::MtAws::MetaData::meta_encode(undef, 4), 'should catche missed filename';
	ok defined App::MtAws::MetaData::meta_encode('filename', 0), 'should allow 0 mtime';
	ok !defined App::MtAws::MetaData::meta_encode('f' x 1024, 0), 'should catch too big string';
	ok defined App::MtAws::MetaData::meta_encode('я' x 350, 0), 'should allow 350 UTF 2 bytes characters';
	ok defined App::MtAws::MetaData::meta_encode('z' x 700, 0), 'should allow 700 ASCII characters';
}

# test _parse_iso8601
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
#		['20081231T235960Z', 1230768000], # leap second is broken
		['20090101T000000Z', 1230768000], # after leap second
		['19070809T082454Z', -1969112106], # negative value
		['19070809T084134Z', -1969111106], # negative value
		['19700101T000000Z', 0],
	) {
		my $result = App::MtAws::MetaData::_parse_iso8601($_->[0]);
		ok($result == $_->[1], 'should parse iso8601');

		my $dt = DateTime->from_epoch( epoch => $_->[1] );
		my $dt_8601 = sprintf("%04d%02d%02dT%02d%02d%02dZ", $dt->year, $dt->month, $dt->day, $dt->hour, $dt->min, $dt->sec);
		ok( $_->[0] eq $dt_8601, "iso8601 $dt_8601 should be correct string");
	}
}

# test different formats _parse_iso8601
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
		my $result = App::MtAws::MetaData::_parse_iso8601($_->[0]);
		ok($result == $_->[1], "should parse iso8601 $result == $_->[1]");
	}
}


# check time converts both ways

is App::MtAws::MetaData::_parse_iso8601("16800101T000000Z"), -9151488000;
is App::MtAws::MetaData::_parse_iso8601("22600101T000000Z"), 9151488000;
is App::MtAws::MetaData::_parse_iso8601("40000201T000000Z"), 64063267200;
is App::MtAws::MetaData::_parse_iso8601("19691231T235950Z"), -10;
is App::MtAws::MetaData::_parse_iso8601("20140114T003509Z"), 1389659709;

is App::MtAws::MetaData::_parse_iso8601("20371231T235959Z"), 2145916799;
is App::MtAws::MetaData::_parse_iso8601("20380101T000000Z"), 2145916800;
is App::MtAws::MetaData::_parse_iso8601("19011231T235959Z"), -2145916801;
is App::MtAws::MetaData::_parse_iso8601("19020101T000000Z"), -2145916800;

ok defined App::MtAws::MetaData::_parse_iso8601(sprintf("2014%02d01T000000Z", $_)) for (1..12);
ok defined App::MtAws::MetaData::_parse_iso8601(sprintf("201401%02dT000000Z", $_)) for (1,2,30,31);
ok defined App::MtAws::MetaData::_parse_iso8601(sprintf("20140101T%02d0000Z", $_)) for (0,1,22,23);
ok defined App::MtAws::MetaData::_parse_iso8601(sprintf("20140101T00%02d00Z", $_)) for (0,1,58,59);
ok defined App::MtAws::MetaData::_parse_iso8601(sprintf("20140101T0000%02dZ", $_)) for (0,1,58,59);

ok !defined App::MtAws::MetaData::_parse_iso8601("20141301T000000Z");
ok !defined App::MtAws::MetaData::_parse_iso8601("20140132T000000Z");
ok !defined App::MtAws::MetaData::_parse_iso8601("20140101T240000Z");
ok !defined App::MtAws::MetaData::_parse_iso8601("20140101T006000Z");
ok !defined App::MtAws::MetaData::_parse_iso8601("20140101T000063Z");

ok !defined App::MtAws::MetaData::_parse_iso8601("09990101T000000Z"), "should disallow years before 1000";
ok defined App::MtAws::MetaData::_to_iso8601(253402300799);
ok !defined App::MtAws::MetaData::_to_iso8601(253402300799+1), "should disallow years after 9999";

# test correctness and consistency of _parse_iso8601 and _to_iso8601
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
					my $r = App::MtAws::MetaData::_parse_iso8601($str);
					if (is_64bit_os) {
						my $str_a = App::MtAws::MetaData::_to_iso8601($r); # reverse
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

# list vs scalar context

{
	my $date = '20121225T100000Z';
	my $result = App::MtAws::MetaData::_parse_iso8601($date);
	my @a = App::MtAws::MetaData::_parse_iso8601($date);
	is $a[0], $result, "should work same way in list context";
}

# test error handling _parse_iso8601
{
	for (qw/20121515T100000Z 1234/) {
		ok ! defined App::MtAws::MetaData::_parse_iso8601($_);
	}
}


# check catching for undef - warning duplicate test found in unit tests
{
	my $called;
	local *App::MtAws::MetaData::decode = sub { $called = 1 };
	ok defined App::MtAws::MetaData::_decode_utf8 encode("UTF-8", "тест");
	ok ($called, "_decode_utf8 calls App::MtAws::MetaData::decode (which is Encode::decode)");
	$called = 0;
	ok !defined App::MtAws::MetaData::_decode_utf8 undef;
	ok !$called, "_decode_utf8 retruns undef even without calling Encode::decode";
}

#
# testing jobs metadata
#

ok App::MtAws::MetaData::meta_job_encode("x");
ok ! defined App::MtAws::MetaData::meta_job_encode("x" x 1024);

for (qw/full 0 x тест µ/, '') {
	cmp_deeply [App::MtAws::MetaData::meta_job_decode(App::MtAws::MetaData::meta_job_encode($_))], [$_], "should decode jobs metadata";
}
cmp_deeply [App::MtAws::MetaData::meta_job_decode('mtijob1 eyJ0eXBlIjoiZnVsbCJ9')], ['full'], "should decode jobs metadata";

{
	my $without_type = "mtijob1 ".App::MtAws::MetaData::_encode_b64(App::MtAws::MetaData::_encode_json({ x => 'y' }));
	ok ! defined App::MtAws::MetaData::meta_job_decode($without_type), "should return undef in case there is no type";
	my @r = App::MtAws::MetaData::meta_job_decode($without_type);
	is scalar @r, 0, "should return empty list in case there is no type";
}

ok ! defined App::MtAws::MetaData::meta_job_decode(undef), 'should return undef if input undef';
ok ! defined App::MtAws::MetaData::meta_job_decode(), 'should return undef if input empty';
ok ! defined App::MtAws::MetaData::meta_job_decode('mtijob11 eyJ0eXBlIjoiZnVsbCJ9'), 'should return undef if wrong marker';
ok ! defined App::MtAws::MetaData::meta_job_decode('mt1 eyJ0eXBlIjoiZnVsbCJ9'), 'should return undef if wrong marker';
ok ! defined App::MtAws::MetaData::meta_job_decode('zzz'), 'should return undef if no marker present';
ok ! defined App::MtAws::MetaData::meta_job_decode('mtijob1 zzz'), 'should return undef if utf is broken';
ok ! defined App::MtAws::MetaData::meta_job_decode('mtijob1 !!!!'), 'should return undef if base64 is broken';
ok ! defined App::MtAws::MetaData::meta_job_decode('mtijob1 z+z'), 'should return undef if base64 is broken';
ok ! defined App::MtAws::MetaData::meta_job_decode('mtijob1 '._encode_base64url('ff')), 'should return undef if json is broken';

sub to_iso8601
{
	strftime("%Y%m%dT%H%M%SZ", gmtime(shift));
}


sub _encode_base64url { # copied from MIME::Base64
	my $e = encode_base64(shift, "");
	$e =~ s/=+\z//;
	$e =~ tr[+/][-_];
	return $e;
}

1;
