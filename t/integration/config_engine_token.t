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
use Test::More tests => 54;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use TestUtils;

warning_fatal();

for (
	[qw!create-vault --config glacier.cfg myvault!],
	[qw!delete-vault --config glacier.cfg myvault!],
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!],
	[qw!upload-file --config glacier.cfg --vault myvault --journal j --dir a --filename a/myfile!],
	[qw!purge-vault --config glacier.cfg --vault myvault --journal j!],
	[qw!restore --config glacier.cfg --vault myvault --journal j --dir a --max-number-of-files 1!],
	[qw!restore-completed --config glacier.cfg --vault myvault --journal j --dir a!],
	[qw!retrieve-inventory --config glacier.cfg --vault myvault!],
	[qw!download-inventory --config glacier.cfg --vault myvault --new-journal j!],
) {
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $token = ('x' x 330);
			my $res = config_create_and_parse(@$_, qq!--token!, $token);
			ok !($res->{errors}||$res->{warnings}), "no errors";
			is $res->{options}{token}, $token, "token matches";
			
			$res = config_create_and_parse(@$_);
			ok !($res->{errors}||$res->{warnings}), "no errors";
			ok !defined($res->{options}{token}), "token is optional";
			
			$token = ('x' x 10);
			$res = config_create_and_parse(@$_, qq!--token!, $token);
			cmp_deeply $res->{errors}, [{a => 'token', format => 'invalid_format', value => $token}], "should catch too small token";

			$token = ('x' x 1500);
			$res = config_create_and_parse(@$_, qq!--token!, $token);
			cmp_deeply $res->{errors}, [{a => 'token', format => 'invalid_format', value => $token}], "should catch too large token";
		}
	}
}

1;
