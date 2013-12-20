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
use Test::More tests => 226;
use Test::Deep;
use Carp;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use Test::MockModule;
use File::Path;
use File::stat;
use Data::Dumper;
use TestUtils;

warning_fatal();


# upload_file command parsing test

my ($default_concurrency, $default_partsize) = (4, 16);

# upload-file


my %common = (
	journal => 'j',
	partsize => $default_partsize,
	concurrency => $default_concurrency,
	key=>'mykey',
	secret => 'mysecret',
	region => 'myregion',
	protocol => 'http',
	vault =>'myvault',
	config=>'glacier.cfg',
	timeout => 180,
	'journal-encoding' => 'UTF-8',
	'filenames-encoding' => 'UTF-8',
	'terminal-encoding' => 'UTF-8',
	'config-encoding' => 'UTF-8'
);

#### PASS

sub assert_passes($$%)
{
	my ($msg, $query, %result) = @_;
	fake_config sub {
		disable_validations qw/journal secret key filename dir/ => sub {
			my $res = config_create_and_parse(split(' ', $query));
			print Dumper $res->{errors} if $res->{errors};
			ok !($res->{errors}||$res->{warnings}), $msg;
			is $res->{command}, 'upload-file', $msg;
			is_deeply($res->{options}, {
				%common,
				%result
			}, $msg);
		}
	}
}

###
### filename
###

## set-rel-filename

assert_passes "should work with filename and set-rel-filename",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --set-rel-filename x/y/z!,
	'name-type' => 'rel-filename',
	relfilename => 'x/y/z',
	'data-type' => 'filename',
	'set-rel-filename' => 'x/y/z',
	filename => '/tmp/dir/a/myfile';


##
## stdin
##

## set-rel-filename

assert_passes "should work with stdin and set-rel-filename",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --check-max-file-size 100!,
	'name-type' => 'rel-filename',
	'data-type' => 'stdin',
	stdin => 1,
	'check-max-file-size' => 100,
	relfilename => 'x/y/z',
	'set-rel-filename' => 'x/y/z';



#### FAIL

sub assert_fails($$%)
{
	my ($msg, $query, $novalidations, $error, %opts) = @_;
	fake_config sub {
		disable_validations qw/journal key secret/, @$novalidations => sub {
			my $res = config_create_and_parse(split(' ', $query));
			ok $res->{errors}, $msg;
			ok !defined $res->{warnings}, $msg;
			ok !defined $res->{command}, $msg;
			cmp_deeply [grep { $_->{format} eq $error } @{ $res->{errors} }], [{%opts, format => $error}], $msg;
		}
	}
}

assert_fails "filename, set-rel-filename should fail with dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j!,
	[],
	'Please specify filename or stdin';

###
### filename
###


assert_fails "filename with fail without set-rel-filename or dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile!,
	['filename'],
	'either', a => 'set-rel-filename', b => 'dir';

## set-rel-filename

assert_fails "filename, set-rel-filename should fail with dir",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --set-rel-filename x/y/z --dir abc!,
	['filename', 'dir'],
	'mutual', a => 'set-rel-filename', b => 'dir';

for (qw!/x/y/z x/../y/z ../y x/./y!) {
assert_fails "should check set-rel-filename to be relative filename for $_",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --filename /tmp/dir/a/myfile --set-rel-filename $_!,
	['filename'],
	'require_relative_filename', a => 'set-rel-filename', value => $_;
}

##
## stdin
##

assert_fails "filename, set-rel-filename should be used with stdin",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin!,
	[],
	'mandatory_with', a => 'set-rel-filename', b => 'stdin';

assert_fails "check-max-file-size should be used with stdin",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z!,
	['dir'],
	'mandatory_with', a => 'check-max-file-size', b => 'stdin';

##
## test for check-max-file-size calculation
##

{
	no warnings 'redefine';
	local *App::MtAws::ConfigDefinition::is_digest_sha_broken_for_large_data = sub { 0 };
	use warnings 'redefine';
	{
		for my $partsize (1, 2, 4, 8, 1024, 2048, 4096) {
			my $edge_size = $partsize * 10_000;
			for my $filesize ($edge_size + 1, $edge_size + 2, $edge_size + 100) {
				assert_fails "check-max-file-size should catch wrong partsize ($partsize, $filesize)",
					qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --partsize $partsize --check-max-file-size $filesize!,
					['dir'],
					'partsize_vs_maxsize', 'maxsize' => 'check-max-file-size', 'partsize' => 'partsize', 'partsizevalue' => $partsize, 'maxsizevalue' => $filesize;
			}
			for my $filesize ($edge_size - 100, $edge_size - 2, $edge_size - 1, $edge_size) {
				assert_passes "should work with filename and set-rel-filename",
					qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --partsize $partsize --check-max-file-size $filesize!,
					'name-type' => 'rel-filename',
					'data-type' => 'stdin',
					stdin => 1,
					'check-max-file-size' => $filesize,
					partsize => $partsize,
					relfilename => 'x/y/z',
					'set-rel-filename' => 'x/y/z';
			}
		}
	}

	{
		my $partsize = 4096;
		my $edge_size = $partsize * 10_000;
		for my $filesize ($edge_size + 1, $edge_size + 2, $edge_size + 100) {
			assert_fails "check-max-file-size too big ($filesize)",
				qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --partsize $partsize --check-max-file-size $filesize!,
				['dir'],
				'maxsize_too_big', 'a' => 'check-max-file-size', value => $filesize;
		}
	}
}

## set-rel-filename

assert_fails "set-rel-filename and dir as mutual exclusize",
	qq!upload-file --config glacier.cfg --vault myvault --journal j --stdin --set-rel-filename x/y/z --dir abc --check-max-file-size 100!,
	['dir'],
	'mutual', a => 'set-rel-filename', b => 'dir';



1;
