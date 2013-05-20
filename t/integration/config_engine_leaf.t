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
use Test::More tests => 21;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use TestUtils;

warning_fatal();



for (
	qw/0 1/
) {
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $res = config_create_and_parse(qw!sync --config glacier.cfg --vault myvault --journal j --dir a!, '--leaf-optimization', $_);
			ok !($res->{errors}||$res->{warnings}), "should accept leaf-optimization $_";
			ok $res->{options}->{'leaf-optimization'} eq $_;
		}
	}
}

for (
	qw/0 1/
) {
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', 'leaf-optimization' => $_, sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $res = config_create_and_parse(qw!sync --config glacier.cfg --vault myvault --journal j --dir a!);
			ok !($res->{errors}||$res->{warnings}), "should accept leaf-optimization from config $_";
			ok $res->{options}->{'leaf-optimization'} eq $_;
		}
	}
}


for (
	qw/true false yes no NO YES TRUE x z/
) {
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $res = config_create_and_parse(qw!sync --config glacier.cfg --vault myvault --journal j --dir a!, '--leaf-optimization', $_);
			ok $res->{errors}, "should not accept leaf-optimization $_";
		}
	}
}


for (
	[qw!purge-vault --config glacier.cfg --vault myvault --journal j!],
	[qw!restore --config glacier.cfg --vault myvault --journal j --dir a --max-number-of-files 1!],
	[qw!restore-completed --config glacier.cfg --vault myvault --journal j --dir a!],
	[qw!check-local-hash --config glacier.cfg --journal j --dir a!],
) {
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $res = config_create_and_parse(@$_, '--leaf-optimization', '1');
			ok $res->{errors}, "$_->[0] should not accept leaf-optimization";
		}
	}
}

1;