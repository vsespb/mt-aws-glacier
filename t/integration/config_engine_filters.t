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
use Test::More tests => 351;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use Test::MockModule;
use Data::Dumper;






sub assert_filters($$@)
{
	my ($msg, $queryref, @parsed) = @_;
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $res = config_create_and_parse(@$queryref);
			#print Dumper $res->{errors};
			ok !($res->{errors}||$res->{warnings}), $msg;
			is scalar (my @got = @{$res->{options}{filters}{parsed}{filters}}), scalar @parsed;
			while (@parsed) {
				my $got = shift @got;
				my $expected = shift @parsed;
				cmp_deeply $got, superhashof $expected;
			}
		}
	}
}

sub assert_fails($$%)
{
	my ($msg, $queryref, $novalidations, $error, %opts) = @_;
	fake_config sub {
		disable_validations qw/journal key secret dir/, @$novalidations => sub {
			my $res = config_create_and_parse(@$queryref);
			ok $res->{errors}, $msg;
			ok !defined $res->{warnings}, $msg;
			ok !defined $res->{command}, $msg;
			is_deeply $res->{errors}, [{%opts, format => $error}], $msg;
		}
	}
}




for (
	[qw!sync --config glacier.cfg --vault myvault --journal j --dir a!],
	[qw!purge-vault --config glacier.cfg --vault myvault --journal j!],
	[qw!restore --config glacier.cfg --vault myvault --journal j --dir a --max-number-of-files 1!],
	[qw!restore-completed --config glacier.cfg --vault myvault --journal j --dir a!],
	[qw!check-local-hash --config glacier.cfg --journal j --dir a!],
) {
	# include
	
	assert_filters "include should work",
		[@$_, '--include', '*.gz'],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)};
	
	assert_filters "two includes should work",
		[@$_, qw!--include *.gz --include *.txt!],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '+', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)};
	
	# exclude
	
	assert_filters "exclude should work",
		[@$_, qw!--exclude *.gz!],
		{ action => '-', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)};
	
	assert_filters "two excludes should work",
		[@$_, qw!--exclude *.gz --exclude *.txt!],
		{ action => '-', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
		;
	# filter
	
	assert_filters "filter should work",
		[@$_, qw!--filter!, '+*.gz'],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)};
	
	assert_filters "double filter should work",
		[@$_, qw!--filter!, '+*.gz -*.txt'],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
		;
	assert_filters "two filters should work",
		[@$_, '--filter', '+*.gz', '--filter', '-*.txt'],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)};
	
	assert_filters "filter + double filter should work",
		[@$_, '--filter', '+*.gz', '--filter', '-*.txt +*.jpeg'],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '+', pattern => '*.jpeg', notmatch => bool(0), match_subdirs => bool(0)};
	
	# include, exclude, filter
	
	assert_filters "filter and include should work",
		[@$_, '--filter', '+*.gz', '--include', '*.txt'],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '+', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)}
		;
	
	assert_filters "filter and exclude should work",
		[@$_, '--filter', '+*.gz', '--exclude', '*.txt'],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)}
		;
	assert_filters "filter + double filter + include + exclude should work",
		[@$_,
		'--filter', '+*.gz', '--filter', '-*.txt +*.jpeg', '--include', 'dir/', '--exclude', 'dir2/'],
		{ action => '+', pattern => '*.gz', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '+', pattern => '*.jpeg', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '+', pattern => 'dir/', notmatch => bool(0), match_subdirs => bool(1)},
		{ action => '-', pattern => 'dir2/', notmatch => bool(0), match_subdirs => bool(1)};
	
	# exclamations
	
	assert_filters "exclude should work",
		[@$_, qw{--exclude !*.gz}],
		{ action => '-', pattern => '!*.gz', notmatch => bool(1), match_subdirs => bool(0)};
	
	assert_filters "filter + double filter + include + exclude should work",
		[@$_, '--filter', '+!*.gz', '--filter', '-*.txt +!*.jpeg', '--include', 'dir/', '--exclude', '!dir2/'],
		{ action => '+', pattern => '!*.gz', notmatch => bool(1), match_subdirs => bool(0)},
		{ action => '-', pattern => '*.txt', notmatch => bool(0), match_subdirs => bool(0)},
		{ action => '+', pattern => '!*.jpeg', notmatch => bool(1), match_subdirs => bool(0)},
		{ action => '+', pattern => 'dir/', notmatch => bool(0), match_subdirs => bool(1)},
		{ action => '-', pattern => '!dir2/', notmatch => bool(1), match_subdirs => bool(0)};
	
	# some edge cases
	
	assert_filters "filter and include should work",
		[@$_, '--filter', '+'],
		{ action => '+', pattern => '', notmatch => bool(0), match_subdirs => bool(1)};
		;

	#### FAIL
	
	
	assert_fails "should catch parse error",
		[@$_, '--filter', ' +z  p +a'],
		[],
		'filter_error', a => 'p +a';
		
	assert_fails "should catch parse error",
		[@$_, '--filter', '+z z'],
		[],
		'filter_error', a => 'z';
		
	assert_fails "should not allow empty filter",
		[@$_, '--filter', ''],
		[],
		'filter_error', a => '';


}

fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', 'filter' => '+*.gz -', sub {
	disable_validations qw/journal secret key filename dir/ => sub {
		my $res = config_create_and_parse(qw!sync --config glacier.cfg --vault myvault --journal j --dir a!);
		cmp_deeply $res->{errors}, [{'format' => 'list_options_in_config', 'option' => 'filter' }];
	}
};

1;
