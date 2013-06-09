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
use Test::More tests => 8;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use TestUtils;

warning_fatal(); # TODO: reenable when get rid of GetOpt warning

sub assert_options($$@)
{
	my $msg = shift;;
	my $expected = shift;;
	my $res = config_create_and_parse(@_);
	ok !($res->{errors}||$res->{warnings}), $msg;
	#use Data::Dumper; print Dumper $res->{errors};
	cmp_deeply $res->{options}, superhashof($expected), $msg;
}

sub assert_segment_error($$@)
{
	my $msg = shift;;
	my $error = shift;;
	my $res = config_create_and_parse(@_);
	print $error;
	cmp_deeply $res->{errors}, $error, $msg;
}

for my $line (
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!],
) {
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			assert_options 'new should be default', { new => 1 }, @$line;
			assert_options 'new should work', { new => 1 }, @$line, '--new';
			my @other_opts = qw/--replace-modified --delete-removed/;
			for (@other_opts) {
				my $res = config_create_and_parse(@$line, $_);
				ok ! exists $res->{options}->{new};
			}
			my $res = config_create_and_parse(@$line, @other_opts);
			ok ! exists $res->{options}->{new};
			$res = config_create_and_parse(@$line, @other_opts, '--new');
			ok $res->{options}->{new};
		}
	}
}

1;