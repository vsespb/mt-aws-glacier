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
use Test::More tests => 39;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils;

#warning_fatal(); # TODO: reenable when get rid of GetOpt warning

sub assert_segment_size($$@)
{
	my $msg = shift;;
	my $expected = shift;;
	my $res = config_create_and_parse(@_);
	ok !($res->{errors}||$res->{warnings}), $msg;
	is $res->{options}{file_downloads}{'segment-size'}, $expected, $msg;
}

sub assert_segment_error($$@)
{
	my $msg = shift;;
	my $error = shift;;
	my $res = config_create_and_parse(@_);
	cmp_deeply $res->{errors}, $error, $msg;
}

for my $line (
	[qw!restore-completed --config glacier.cfg --vault myvault --journal j --dir a!],
) {
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			assert_segment_size '0 size allowed', 0, @$line, qq!--segment-size!, 0;
			{
				local $SIG{__WARN__} = sub { $_[0] =~ /invalid for option segment\-size/ or die "Wrong error message $_[0]" };
				assert_segment_error "non-number size invalid", [{format => 'getopts_error'}], @$line, qq!--segment-size!, 'x';
			}
			assert_segment_size "$_ size allowed", $_, @$line, qq!--segment-size!, $_
				for (qw/1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192 16384/);
			assert_segment_error "$_ size invalid", [{a => 'segment-size', format => '%option a% must be zero or power of two', value => $_}],
				@$line, qq!--segment-size!, $_
					for (qw/3 5 7 6 18 222/)
		}
	}
}

1;
