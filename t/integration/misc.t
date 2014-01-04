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
use Test::More tests => 11;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils;
use App::MtAws;
use App::MtAws::Utils;

use Digest::SHA;
use Config;

warning_fatal();


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

1;
