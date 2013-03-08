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
use Test::More tests => 122;
use Test::Deep;
use Encode;
use lib qw{../lib ../../lib};
use App::MtAws::Filter qw/_parse_filters/;
use Data::Dumper;



sub assert_parse_filter_error($$)
{
	my ($data, $err) = @_;
	cmp_deeply [_parse_filters($data)], [undef, $err];
}

sub assert_parse_filter_ok(@$)
{
	my ($expected, @data) = (pop, @_);
	cmp_deeply [_parse_filters(@data)], [$expected, undef];
}


my @spaces = ('', ' ', '  ');
my @onespace = ('', ' ');

for my $before (@spaces) {
	for my $after (@spaces) {
		for my $sign (qw/+ -/) {
			for my $last (@spaces) {
				assert_parse_filter_ok "${before}${sign}${after}*.gz${last}", [[$sign, '*.gz']];
			}
		}
	}
}

for my $between (' ', '  ') {
	for my $before (@onespace) {
		for my $after (@onespace) {
			for my $last (@onespace) {
				my ($res, $err);
				
				assert_parse_filter_ok "${before}+${after}*.gz${last}${between}${before}-${after}*.txt${last}", [['+', '*.gz'], ['-', '*.txt']];
				
				assert_parse_filter_ok
					"${before}+${after}*.gz${last}${between}${before}-${after}*.txt${last}",
					"${before}-${after}*.jpeg${last}${between}${before}+${after}*.png${last}",
					[['+', '*.gz'], ['-', '*.txt'], ['-', '*.jpeg'], ['+', '*.png']];

				assert_parse_filter_ok
					"${before}+${after}*.gz${last}${between}${before}-${after}*.txt${last}",
					"${before}-${after}*.jpeg${last}${between}",
					[['+', '*.gz'], ['-', '*.txt'], ['-', '*.jpeg']];
				
				assert_parse_filter_ok
					"${between}${before}-${after}*.txt${last}",
					"${before}-${after}*.jpeg${last}${between}${before}+${after}*.png${last}",
					[['-', '*.txt'], ['-', '*.jpeg'], ['+', '*.png']];
			}
		}
	}
}


assert_parse_filter_error ' +z  p +a', 'p +a';
assert_parse_filter_error '+z z', 'z';
assert_parse_filter_error '', '';
assert_parse_filter_error ' ', ' ';




1;
