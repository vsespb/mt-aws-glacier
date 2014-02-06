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
use Test::More tests => 17;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws;
use App::MtAws::Utils;
use Config;

use Digest::SHA;
use Config;

#
# test what untested in perl
#

{
	my $i = 0;
	while () {
		last if ++$i == 3;
	}
	is $i, 3, "while() should produce infinite loop";
}

{
	my $i = 0;
	alarm 3;
	++$i while ();
	alarm 0;
	is $i, 0, "while() without block should not produce infinite loop";
}


#
# Utils.pm
#

sub test_is_digest_sha_broken_for_large_data
{
	my ($longsize, $module_version, $result) = @_;
	no warnings 'redefine';
	local *App::MtAws::Utils::get_config_var = sub { $longsize };
	local $Digest::SHA::VERSION = $module_version;
	if ($result) {
		ok is_digest_sha_broken_for_large_data();
	} else {
		ok !is_digest_sha_broken_for_large_data();
	}
}

is is_digest_sha_broken_for_large_data(), $Config{'longsize'} < 8 && $Digest::SHA::VERSION lt '5.62';

test_is_digest_sha_broken_for_large_data(4, '5.61', 1);

test_is_digest_sha_broken_for_large_data(4, '5.62', 0);
test_is_digest_sha_broken_for_large_data(4, '5.619999999999', 1);

test_is_digest_sha_broken_for_large_data(4, '5.63', 0);
test_is_digest_sha_broken_for_large_data(8, '5.61', 0);
test_is_digest_sha_broken_for_large_data(8, '5.62', 0);
test_is_digest_sha_broken_for_large_data(8, '5.63', 0);
test_is_digest_sha_broken_for_large_data(4, '5.84_01', 0);

SKIP: {
	skip "cant test this", 1 unless $^O eq 'linux' && $Config{'longsize'} >= 8;
	ok is_64bit_time, "at least sometimes is_64bit_time returns true";
}

SKIP: {
	skip "This installation possibly does not support Y2038", 3
		unless
		(
			($^V ge v5.12.0) ||
			(
				is_64bit_time &&
				($^V eq v5.8.9 or $^V ge v5.10.1)
			)
		);
	ok is_y2038_supported, "make sure is_y2038_supported at least sometimes returns true";

	{
		my $count = 0;
		no warnings 'redefine';
		local *App::MtAws::Utils::timegm = sub { ++$count; die "MOCK DIE"; };
		local $App::MtAws::Utils::_is_y2038_supported = undef;
		is_y2038_supported();
		my $err = $@;
		like $err, qr/MOCK DIE/;
		is_y2038_supported();
		is $count, 1, "should be cached even if eval failed";
	}

}

is_y2038_supported(); # should not issue warning;

{
	local $App::MtAws::Utils::_is_y2038_supported = 42;
	is is_y2038_supported, 42, "make sure is_y2038_supported is cached";
	is is_y2038_supported, 42, "make sure is_y2038_supported is cached. again.";
}


1;
