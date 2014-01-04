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
use Test::More tests => 173;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils;

warning_fatal(); # TODO: reenable when get rid of GetOpt warning

sub assert_options($$@)
{
	my $msg = shift;;
	my $expected = shift;;
	my $res = config_create_and_parse(@_);
	ok !($res->{errors}||$res->{warnings}), $msg;
	cmp_deeply $res->{options}, superhashof($expected), $msg;
}

sub assert_error($$@)
{
	my $msg = shift;;
	my $error = shift;;
	my $res = config_create_and_parse(@_);
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

			for my $other_opts (
				[{}],
				[{ new => 1}, '--new'],
				[{'delete-removed' => 1}, '--delete-removed'],
			) {
				my @other_opts_a = @$other_opts;
				my $addhash = shift @other_opts_a;
				assert_error "detect with wrong value should not work without replace-modified (while ".
					(@other_opts_a ? join(',', @other_opts_a) : 'no other options').
					" is active)",
						[{'format' => 'option_for_command_can_be_used_only_with', a => 'detect', b => 'replace-modified', c => 'sync'},
						{'format' => 'invalid_format', a => 'detect', value => 'xyz'}],
						@$line, '--detect', 'xyz', @other_opts_a;

				for (qw/treehash mtime mtime-and-treehash mtime-or-treehash always-positive size-only/) {
					assert_options "detect=$_ should work with replace-modified (while ".
						(@other_opts_a ? join(',', @other_opts_a) : 'no other options').
						" is active)",
							{ 'detect' => $_, %$addhash },
							@$line, '--replace-modified', '--detect', $_, @other_opts_a;

					assert_error "detect=$_ should not work without replace-modified (while ".
						(@other_opts_a ? join(',', @other_opts_a) : 'no other options').
						" is active)",
							[{'format' => 'option_for_command_can_be_used_only_with', a => 'detect', b => 'replace-modified', c => 'sync'}],
							@$line, '--detect', $_, @other_opts_a;

					fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', detect => $_, sub {
						assert_options "detect=$_ in config should work with replace-modified (while ".
							(@other_opts_a ? join(',', @other_opts_a) : 'no other options').
							" is active)",
								{ 'detect' => $_, %$addhash },
								@$line, '--replace-modified', '--detect', $_, @other_opts_a;

						assert_options "detect=$_ in config should not work without replace-modified (while ".
							(@other_opts_a ? join(',', @other_opts_a) : 'no other options').
							" is active)",
								{ 'detect' => $_, %$addhash },
								@$line, @other_opts_a;

					};

					fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', detect => $_, 'replace-modified' => 1, sub {
						assert_options "detect=$_ in config should work with replace-modified in config (while ".
							(@other_opts_a ? join(',', @other_opts_a) : 'no other options').
							" is active)",
								{ 'detect' => $_, %$addhash },
								@$line, '--detect', $_, @other_opts_a;
					}
				}
			}
		}
	}
}

1;
