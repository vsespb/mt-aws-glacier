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
use Test::More tests => 4154;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::MetaData;
use Encode;
use JSON::XS;
use POSIX;



my $meta_coder = JSON::XS->new->utf8;

for my $char1 (qw/a b c d e f _ ß µ Ũ  а б в г д е ё ж з и к л м н о п р с т у ф ц ч ш щ э ю я А Б В Г Д Е Ё Ж З И К Л М Н О П Р С Т У Ф Х Ц Ч Ш Щ Э Ю Я/) {
	test($char1);
	for my $char2 (qw/a _ ß µ Ũ  а  я А Б  Я/) {
		test($char1.$char2);
		test($char1.'/'.$char2);
		test($char1.'A'.$char2);
	}
}

sub test
{
	my ($str) = @_;
	my ($res, $mtime) = App::MtAws::MetaData::meta_decode(mt1_meta_encode($str, 123));
	ok $res eq $str;
	ok $mtime == 123;
}



sub mt1_meta_encode
{
	my ($relfilename, $mtime) = @_;
	return unless defined($mtime) && defined($relfilename);
	my $res = "mt1 ".mt1_encode_b64(mt1_encode_utf8(mt1_encode_json($relfilename, $mtime)));
	return if length($res) > 1024;
	return $res;
}

sub mt1_encode_b64
{
	my ($str) = @_;
	my $res = MIME::Base64::encode_base64($str,'');
	$res =~ s/=+\z//;
	$res =~ tr{+/}{-_};
	return $res;
}

sub mt1_encode_utf8
{
	my ($str) = @_;
	return encode("UTF-8",$str,Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
}


sub mt1_encode_json
{
	my ($relfilename, $mtime) = @_;
	
	return $meta_coder->encode({
		mtime => strftime("%Y%m%dT%H%M%SZ", gmtime($mtime)),
		filename => $relfilename
	}),
}

1;