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
use Test::More tests => 6;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use Test::MockModule;
use Data::Dumper;
use TestUtils;

warning_fatal();

# v0.82 regressions test


my ($default_concurrency, $default_partsize) = (4, 16);
my %misc_opts = ('journal-encoding' => 'UTF-8', 'filenames-encoding' => 'UTF-8', 'terminal-encoding' => 'UTF-8', 'config-encoding' => 'UTF-8', timeout => 180);

# retrieve-inventory

for (
	qq!retrieve-inventory --config=glacier.cfg --vault=myvault!,
){
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && !$warnings, "$_ error/warnings");
		ok ($command eq 'retrieve-inventory', "$_ command");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
		}, "$_ result");
	};
}

# download-inventory

for (
	qq!download-inventory --config=glacier.cfg --vault=myvault --new-journal=new-journal.log!,
){
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && !$warnings, "$_ error/warnings");
		ok ($command eq 'download-inventory', "$_ command");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			'new-journal' => 'new-journal.log',
			config=>'glacier.cfg',
		}, "$_ result");
	}
}



1;