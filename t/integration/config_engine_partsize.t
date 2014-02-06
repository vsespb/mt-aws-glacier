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
use Test::More tests => 86;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::Utils;

sub assert_partsize($$@) # should have same number of assertions as assert_partsize_error
{
	my $msg = shift;;
	my $expected = shift;;
	my $res = config_create_and_parse(@_);
	ok !($res->{errors}||$res->{warnings}), $msg;
	is $res->{options}{partsize}, $expected, $msg;
}

sub assert_partsize_error($$@) # should have same number of assertions as assert_partsize
{
	my $msg = shift;;
	my $error = shift;;
	my $res = config_create_and_parse(@_);
	ok $res->{errors}, $msg;
	cmp_deeply $res->{errors}, $error, $msg;
}

my @broken_sha_err = (a => 'partsize', format => 'On 32 bit systems, when Digest::SHA module version < 5.62, %option a% must be less or equal to 256');

for my $line (
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a --concurrency=1!],
) {
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			for (1, (map { 2**$_ } 1..12)) {
				if (is_digest_sha_broken_for_large_data && $_ > 256) {
					assert_partsize_error "$_ size invalid when is_digest_sha_broken_for_large_data",
						[{@broken_sha_err, value => $_}],
						@$line, qq!--partsize!, $_
				} else {
					assert_partsize "$_ partsize allowed", $_, @$line, qq!--partsize!, $_;
				}
			}
			for (0, (map { (2**$_+1, 2**$_-1) } 2..11)) {
				assert_partsize_error "$_ size invalid", [
					{a => 'partsize', format => 'Part size must be power of two', value => $_},
					(is_digest_sha_broken_for_large_data && $_ > 256) ?
						({@broken_sha_err, value => $_}) :
						()
				],
				@$line, qq!--partsize!, $_
			}

			for (2**13, 2**14, 2**15) {
				assert_partsize_error "$_ size invalid", [
					{a => 'partsize', format => '%option a% must be less or equal to 4096', value => $_},
					(is_digest_sha_broken_for_large_data && $_ > 256) ?
						({@broken_sha_err, value => $_}) :
						()
				],
				@$line, qq!--partsize!, $_
			}
			for (map { (2**$_+1, 2**$_-1) } 13..15) {
				assert_partsize_error "$_ size invalid", [
					{a => 'partsize', format => 'Part size must be power of two', value => $_},
					{a => 'partsize', format => '%option a% must be less or equal to 4096', value => $_},
					(is_digest_sha_broken_for_large_data && $_ > 256) ?
						({@broken_sha_err, value => $_}) :
						()
				],
				@$line, qq!--partsize!, $_
			}
		}
	}
}

1;
