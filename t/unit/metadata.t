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
use Test::Spec;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::MetaData;
use Encode;
use JSON::XS;
use Data::Dumper;
use TestUtils;

warning_fatal();

describe "MetaData" => sub {
	it "should catch undef in _decode_json" => sub {
		JSON::XS->expects("decode");
		App::MtAws::MetaData::_decode_json App::MtAws::MetaData::_encode_json('тест', 1);
		JSON::XS->expects("decode")->never();
		ok !defined App::MtAws::MetaData::_decode_json undef;
		
	};
	it "should not call encode" => sub {
		App::MtAws::MetaData->expects("_encode_utf8")->never();
		App::MtAws::MetaData::meta_encode('тест', 1);
		ok 1;
	};
	it "should not call decode for current metadata version" => sub {
		App::MtAws::MetaData->expects("_decode_utf8")->never();
		App::MtAws::MetaData::meta_decode App::MtAws::MetaData::meta_encode('тест', 1);
		ok 1;
	};
	it "should call decode for mt1" => sub {
		App::MtAws::MetaData->expects("_decode_utf8")->once();
		App::MtAws::MetaData::meta_decode 'mt1 eyJmaWxlbmFtZSI6IsOQwq9Bw5DCryIsIm10aW1lIjoiMTk3MDAxMDFUMDAwMjAzWiJ9'
	};
	it "should catch undef in _decode_utf8" => sub {
		App::MtAws::MetaData->expects("decode");
		App::MtAws::MetaData::_decode_utf8 encode("UTF-8", "тест");
		App::MtAws::MetaData->expects("decode")->never();
		ok !defined App::MtAws::MetaData::_decode_utf8 undef;
	};
};

runtests unless caller;

1;