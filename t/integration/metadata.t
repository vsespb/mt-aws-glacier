#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 119;
use Test::Deep;
use lib qw{.. ../..};
use MetaData;

use Test::MockModule;
use MIME::Base64 qw/encode_base64url/;
use Encode;
use Data::Dumper;

no warnings 'redefine';


# test _encode_b64/_decode_b64
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
		my $result = MetaData::_encode_b64($_);
		ok ($result eq encode_base64url(encode("UTF-8", $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)), 'match base64 encode');
		ok ($result !~ /[\r\n]/m, 'does not contain linefeed');
		ok ($result !~ /[\+\/\=]/m, 'does not contain + and /');
		ok (MetaData::_decode_b64($result) eq $_, 'reverse decodable');
	}
}



# test _encode_b64/_decode_b64 with raw fixtures
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
		ok (MetaData::_encode_b64($_->[0]) eq $_->[1], 'base64 match fixture');
		ok (MetaData::_decode_b64($_->[1]) eq $_->[0], 'fixture match base64');
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
		ok( $result =~ /\:\s*$_->[1]/, "result should contain mtime as numeric");
		is_deeply($recoded, { mtime => $_->[1], filename => $_->[0]}, "jsone string should be json with correct filename and mtime");
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
		['file', 1352924178, 'mt1 eyJmaWxlbmFtZSI6ImZpbGUiLCJtdGltZSI6MTM1MjkyNDE3OH0'],
		['file/a',1351924178, 'mt1 eyJmaWxlbmFtZSI6ImZpbGUvYSIsIm10aW1lIjoxMzUxOTI0MTc4fQ'],
		['file/a/b/c/d','1352124178', 'mt1 eyJmaWxlbmFtZSI6ImZpbGUvYS9iL2MvZCIsIm10aW1lIjoxMzUyMTI0MTc4fQ'],
		['директория/a/b/c/d','1352124178', 'mt1 eyJmaWxlbmFtZSI6IsOQwrTDkMK4w5HCgMOQwrXDkMK6w5HCgsOQwr7DkcKAw5DCuMORwo8vYS9iL2MvZCIsIm10aW1lIjoxMzUyMTI0MTc4fQ'],
		['директория/файл',1352124178, 'mt1 eyJmaWxlbmFtZSI6IsOQwrTDkMK4w5HCgMOQwrXDkMK6w5HCgsOQwr7DkcKAw5DCuMORwo8vw5HChMOQwrDDkMK5w5DCuyIsIm10aW1lIjoxMzUyMTI0MTc4fQ'],
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
	ok defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "a", "mtime": 1}').'=='), 'should allow base64 padding';
	ok defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "a", "mtime": 1}').'='), 'should allow base64 padding';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('ff')), 'should return undef if json is broken';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "a": 1, "x": 2}')), 'should return undef if filename and mtime missed';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "f", "x": 2}')), 'should return undef if mtime missed';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "x": 1, "mtime": 2}')), 'should return undef if filename missed';
	ok !defined MetaData::meta_decode('mt1 '.encode_base64url('{ "filename": "a", "mtime": -1}')), 'should return undef if filename missed';
	
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
	ok defined MetaData::meta_encode('я' x 128, 0), 'should aalow 128 UTF characters';
	ok defined MetaData::meta_encode('z' x 256, 0), 'should aalow 256 ASCII characters';
}

1;