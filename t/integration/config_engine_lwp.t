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
use Test::More;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils;
use Test::Deep;
use Data::Dumper;
use LWP::UserAgent;

warning_fatal();



if((LWP->VERSION() >= 6) && (LWP::UserAgent->is_protocol_supported("https")) && (LWP::Protocol::https->VERSION && LWP::Protocol::https->VERSION >= 6)) {
	plan tests => 20;
} else {
	plan skip_all => 'Test cannot be performed witht LWP 6+ and LWP::Protocol::https 6+';
}


for (
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!],
	[qw!purge-vault --config glacier.cfg --vault myvault --journal j!],
	[qw!restore --config glacier.cfg --vault myvault --journal j --dir a --max-number-of-files 1!],
	[qw!restore-completed --config glacier.cfg --vault myvault --journal j --dir a!],
	[qw!check-local-hash --config glacier.cfg --journal j --dir a!],
) {
	fake_config  key=>'mykey', secret => 'mysecret', region => 'myregion', protocol => 'https', sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			no warnings 'redefine';
	
			my $res = config_create_and_parse(@$_);
			ok ! defined $res->{errors};
	
			{
				local *LWP::UserAgent::is_protocol_supported = sub { 0 };
				my $res = config_create_and_parse(@$_);
				cmp_deeply $res->{errors}, ['IO::Socket::SSL or LWP::Protocol::https is not installed'];
			}
			
			{
				local *LWP::VERSION = sub { 5 };
				my $res = config_create_and_parse(@$_);
				cmp_deeply $res->{errors}, ['LWP::UserAgent 6.x required to use HTTPS'];
			}
			
			{
				local *LWP::Protocol::https::VERSION = sub { 5 };
				my $res = config_create_and_parse(@$_);
				cmp_deeply $res->{errors}, ['LWP::Protocol::https 6.x required to use HTTPS'];
			}
		}
	};
}

1;