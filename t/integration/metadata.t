#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 180;
use Test::Deep;
use lib qw{.. ../..};
use MetaData;

use Test::MockModule;
use MIME::Base64 qw/encode_base64url encode_base64/;
use Encode;
use JSON::XS;
use Data::Dumper;
use POSIX;
use DateTime;

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
		my $result = MetaData::_encode_b64(MetaData::_encode_utf8($_));
		ok ($result eq encode_base64url(encode("UTF-8", $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)), 'match base64 encode');
		ok ($result !~ /[\r\n]/m, 'does not contain linefeed');
		ok ($result !~ /[\+\/\=]/m, 'does not contain + and /');
		my $redecoded = MetaData::_decode_utf8(MetaData::_decode_b64($result));
		
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
		my $str = MetaData::_decode_b64($_);
		my $rebase64 = MetaData::_encode_b64($str);
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
		my $base64url = MetaData::_encode_b64($_);
		ok ($base64url !~ /=/g, "_enocde_b64 should not pad base64 $_");
		ok (MetaData::_decode_b64($base64url) eq $_, "_decode_b64 should work without padding $_ $base64url");
		
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
		my $base64url = MetaData::_encode_b64($_);
		local *MIME::Base64::decode_base64 = sub { ($last_arg) = @_;};
		MetaData::_decode_b64($base64url);
		ok ($last_arg eq $base64, "$last_arg eq $base64");
	}
}

# test _encode_b64/_decode_b64 EOL
{
	my $base64 = MetaData::_encode_b64('x' x 1024);
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
		ok (MetaData::_encode_b64(MetaData::_encode_utf8($_->[0])) eq $_->[1], 'base64 match fixture');
		ok (MetaData::_decode_utf8(MetaData::_decode_b64($_->[1])) eq $_->[0], 'fixture match base64');
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
	) {
		my $result = MetaData::_encode_json($_->[0], $_->[1]);
		my $recoded = JSON::XS->new->utf8->allow_nonref->decode($result);
		ok ($result !~ /[\r\n]/m, 'no linefeed');
##		ok( $result =~ /\:\s*$_->[1]/, "result should contain mtime as numeric");
		is_deeply($recoded, { mtime => to_iso8601($_->[1]), filename => $_->[0]}, "jsone string should be json with correct filename and mtime");
		my $result_decoded =decode("UTF-8", $result, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
		ok ($result_decoded =~ /\Q$_->[0]\E/m, "json string should contain UTF without escapes");
		
		my ($filename, $mtime) = MetaData::_decode_json($result);
		ok ($filename eq $_->[0], 'filename match');
		ok ($mtime == $_->[1], 'mtime match');
	}
}

# test meta_encode/meta_decode with fixtures
{
	for (
		['file', 1352924178, 'mt1 eyJmaWxlbmFtZSI6ImZpbGUiLCJtdGltZSI6IjIwMTIxMTE0VDIwMTYxOFoifQ'],
		['file/a',1351924178, 'mt1 eyJmaWxlbmFtZSI6ImZpbGUvYSIsIm10aW1lIjoiMjAxMjExMDNUMDYyOTM4WiJ9'],
		['file/a/b/c/d','1352124178', 'mt1 eyJmaWxlbmFtZSI6ImZpbGUvYS9iL2MvZCIsIm10aW1lIjoiMjAxMjExMDVUMTQwMjU4WiJ9'],
		['директория/a/b/c/d','1352124178', 'mt1 eyJmaWxlbmFtZSI6IsOQwrTDkMK4w5HCgMOQwrXDkMK6w5HCgsOQwr7DkcKAw5DCuMORwo8vYS9iL2MvZCIsIm10aW1lIjoiMjAxMjExMDVUMTQwMjU4WiJ9'],
		['директория/файл',1352124178, 'mt1 eyJmaWxlbmFtZSI6IsOQwrTDkMK4w5HCgMOQwrXDkMK6w5HCgsOQwr7DkcKAw5DCuMORwo8vw5HChMOQwrDDkMK5w5DCuyIsIm10aW1lIjoiMjAxMjExMDVUMTQwMjU4WiJ9'],
	) {
		ok $_->[2] eq MetaData::meta_encode($_->[0], $_->[1]), "check meta_encode";
		
		my ($filename, $mtime) = MetaData::meta_decode($_->[2]);
		ok $_->[0] eq $filename, 'check filename';
		ok $_->[1] eq $mtime, 'check mtime';
	}
}

# test error catch while decoding
{
	ok !defined MetaData::meta_decode('zzz'), 'should return undef if no marker present';
	ok !defined MetaData::meta_decode('mt1 zzz'), 'should return undef if utf is broken';
	ok !defined MetaData::meta_decode('mt1 !!!!'), 'should return undef if base64 is broken';
	ok !defined MetaData::meta_decode('mt1 z+z'), 'should return undef if base64 is broken';
	ok defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}').'=='), 'should allow base64 padding';
	ok defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}').'='), 'should allow base64 padding';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('ff')), 'should return undef if json is broken';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "a": 1, "x": 2}')), 'should return undef if filename and mtime missed';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "f", "x": 2}')), 'should return undef if mtime missed';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "x": 1, "mtime": 2}')), 'should return undef if filename missed';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "a", "mtime": "zzz"}')), 'should return undef if time is broken';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "'.('x' x 1024).'", "mtime": 1}')), 'should return undef if b64 too big';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "f", "mtime": "20081302T222324Z"}')), 'should return undef if b64 too big';
	
	ok defined MetaData::meta_decode('mt1   '.encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}')), 'should allow few spaces';
	ok defined MetaData::meta_decode("mt1\t\t".encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}')), 'should allow tabs';
	ok defined MetaData::meta_decode(" \tmt1\t\t ".encode_base64url('{ "filename": "a", "mtime": "20080102T222324Z"}')), 'should allow leading spaces';
	
	eval { MetaData::meta_decode('zzz') };
	ok $@ eq '', 'should not override eval code';
	
	eval { MetaData::meta_decode('mt1 zzz') };
	ok $@ eq '', 'should not override eval code';

}


# test error cacth while encoding
{
	ok !defined MetaData::meta_encode('filename', -1), 'should catche negative mtime';
	ok !defined MetaData::meta_encode('filename'), 'should catche missed mtime';
	ok !defined MetaData::meta_encode(undef, 4), 'should catche missed filename';
	ok defined MetaData::meta_encode('filename', 0), 'should allow 0 mtime';
	ok !defined MetaData::meta_encode('f' x 1024, 0), 'should catch too big string';
	ok defined MetaData::meta_encode('я' x 128, 0), 'should allow 128 UTF characters';
	ok defined MetaData::meta_encode('z' x 256, 0), 'should allow 256 ASCII characters';
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
	) {
		my $result = MetaData::_parse_iso8601($_->[0]);
		ok($result == $_->[1], 'should parse iso8601');
		
		my $dt = DateTime->from_epoch( epoch => $_->[1] );
		my $dt_8601 = sprintf("%04d%02d%02dT%02d%02d%02dZ", $dt->year, $dt->month, $dt->day, $dt->hour, $dt->min, $dt->sec);
		ok( $_->[0] eq $dt_8601, 'iso8601 should be correct string');
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
	) {
		my $result = MetaData::_parse_iso8601($_->[0]);
		ok($result == $_->[1], 'should parse iso8601');
	}
}


sub to_iso8601
{
	strftime("%Y%m%dT%H%M%SZ", gmtime(shift));
}

1;