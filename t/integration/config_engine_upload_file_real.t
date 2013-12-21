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
use Test::More tests => 194;
use Test::Deep;
use Carp;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use Test::MockModule;
use File::Path;
use File::stat;
use Encode;
use Data::Dumper;
use TestUtils;

use App::MtAws::Utils;

warning_fatal();

my $mtroot = get_temp_dir();

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
	'terminal-encoding' => 'UTF-8',
	'config-encoding' => 'UTF-8'
);


#
# some integration testing
#

sub assert_passes_on_filesystem($$%)
{
	my ($msg, $query, %result) = @_;
	fake_config sub {
		disable_validations qw/journal secret key/ => sub {
			my $res = config_create_and_parse(@$query);
			print Dumper $res->{error_texts} if $res->{errors};
			ok !($res->{errors}||$res->{warnings}), $msg;
			is $res->{command}, 'upload-file', $msg;
			is_deeply($res->{options}, {
				%common,
				%result
			}, $msg);
		}
	}
}

sub assert_fails_on_filesystem($$%)
{
	my ($msg, $query, $novalidations, $error, %opts) = @_;
	fake_config sub {
		disable_validations qw/journal key secret/, @$novalidations => sub {
			my $res = config_create_and_parse(@$query);
			print Dumper $res->{options} unless $res->{errors};
			ok $res->{errors}, $msg;
			ok !defined $res->{warnings}, $msg;
			ok !defined $res->{command}, $msg;
			cmp_deeply [grep { $_->{format} eq $error } @{ $res->{errors} }], [{%opts, format => $error}], $msg;
		}
	}
}


sub test_file_and_dir
{
	my ($msg, $dir, $filename, $expected, $encoding) = @_;

	my $filename_enc = encode("UTF-8", $filename, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	my $dir_enc = encode("UTF-8", $dir, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	$encoding ||= "UTF-8";
	local $App::MtAws::Utils::_filename_encoding = undef;

	assert_passes_on_filesystem $msg,
		[qw!upload-file --config glacier.cfg --vault myvault --journal j!, '--filename', $filename_enc, '--dir', $dir_enc,'--filenames-encoding', $encoding],
		'name-type' => 'dir',
		'data-type' => 'filename',
		relfilename => $expected,
		dir => $dir,
		filename => $filename,
		'filenames-encoding' => $encoding;
}

sub fails_file_and_dir
{
	my ($msg, $dir, $filename, $error, %opts) = @_;
	assert_fails_on_filesystem $msg,
		[qw!upload-file --config glacier.cfg --vault myvault --journal j!, '--filename', $filename, '--dir', $dir],
		[],
		$error, %opts;
}



sub with_save_dir(&)
{
	my $curdir = Cwd::getcwd;
	shift->();
	chdir $curdir or confess;
}

sub with_my_dir($%)
{
	my ($d, $cb, @dirs) = (shift, pop, @_);
	my $dir = "$mtroot/$d";
	with_save_dir {
		mkpath binaryfilename $dir;
		mkpath binaryfilename "$mtroot/$_" for (@dirs);
		chdir binaryfilename $dir or confess;
		$cb->($dir);
	}
}

sub touch
{
	my ($filename, $content) = (@_, "1");
	open my $f, ">", binaryfilename $filename or confess;
	print $f $content;
	close $f;
}

with_my_dir "d1/d2", sub {
	touch "myfile";
	test_file_and_dir "dir/filename should work with ..",
		".", "myfile", "myfile";
	test_file_and_dir "dir/filename should work with ..",
		"..", "myfile", "d2/myfile";
	test_file_and_dir "dir/filename should work with ../..",
		"../..", "myfile", "d1/d2/myfile";
};


SKIP: {
	skip "Test cannot be performed on character-oriented filesystem", 36 unless can_work_with_non_utf8_files;
	for my $encoding (qw/UTF-8 CP1251 KOI8-R/) {
		local $App::MtAws::Utils::_filename_encoding = $encoding;
		with_my_dir "д1/д2", sub {
			touch "мойфайл";
			test_file_and_dir "dir/filename should work with ..",
				".", "мойфайл", "мойфайл", $encoding;
			test_file_and_dir "dir/filename should work with ..",
				"../д2", "мойфайл", "мойфайл", $encoding;
			test_file_and_dir "dir/filename should work with ..",
				"..", "мойфайл", "д2/мойфайл", $encoding;
			test_file_and_dir "dir/filename should work with ../..",
				"../..", "мойфайл", "д1/д2/мойфайл", $encoding;
		};
	}
}

with_my_dir "d1/d2", "d1/d2/d3", sub {
	my ($curdir) = @_;

	touch "d3/myfile";

	test_file_and_dir "dir/filename should work with ..",
		"d3", "d3/myfile", "myfile";
	test_file_and_dir "dir/filename should work with ..",
		"d3/", "d3/myfile", "myfile";
	test_file_and_dir "dir/filename should work with ..",
		"$curdir/d3/", "d3/myfile", "myfile";


	test_file_and_dir "dir/filename should work with ..",
		".", "d3/myfile", "d3/myfile";
	test_file_and_dir "dir/filename should work with ..",
		"..", "d3/myfile", "d2/d3/myfile";
	test_file_and_dir "dir/filename should work with ../..",
		"../..", "d3/myfile", "d1/d2/d3/myfile";
	test_file_and_dir "dir/filename should work with ../..",
		"../d2", "d3/myfile", "d3/myfile";
	test_file_and_dir "dir/filename should work with ../..",
		"../d2/../d2", "d3/myfile", "d3/myfile";
	test_file_and_dir "dir/filename should work with ../..",
		"../d2/.", "./d3/myfile", "d3/myfile";
	test_file_and_dir "dir/filename should work with ../..",
		"../d2", "../d2/d3/myfile", "d3/myfile";
	test_file_and_dir "dir/filename should work with ../..",
		".", "../d2/d3/myfile", "d3/myfile";
	test_file_and_dir "dir/filename should work with ../..",
		"../..", "../../d1/d2/d3/myfile", "d1/d2/d3/myfile";
};

with_my_dir "d1/d2", "d1/d2/d3", "d1/d2/d3/d4", sub {
	touch "d3/myfile";
	touch "d3/d4/myfile2";
	symlink "d3", "ds" or confess;

	test_file_and_dir "dir/filename should work with symlinks 1",
		"d3", "d3/myfile", "myfile";

	test_file_and_dir "dir/filename should work with symlinks 1",
		"d3/", "d3/myfile", "myfile";

	test_file_and_dir "dir/filename should work with symlinks 2",
		"ds", "d3/myfile", "myfile";

	test_file_and_dir "dir/filename should work with symlinks 3",
		"d3", "ds/myfile", "myfile";

	test_file_and_dir "dir/filename should work with symlinks 4",
		"ds", "ds/myfile", "myfile";


	test_file_and_dir "dir/filename should work with symlinks 5",
		"d3", "d3/d4/myfile2", "d4/myfile2";

	test_file_and_dir "dir/filename should work with symlinks 6",
		"ds", "d3/d4/myfile2", "d4/myfile2";

	test_file_and_dir "dir/filename should work with symlinks 7",
		"d3", "ds/d4/myfile2", "d4/myfile2";

	test_file_and_dir "dir/filename should work with symlinks 8",
		"ds", "ds/d4/myfile2", "d4/myfile2";

	test_file_and_dir "dir/filename should work with symlinks 8",
		"ds/", "ds/d4/myfile2", "d4/myfile2";
};


my @filename_inside_dir = ('filename_inside_dir', a => 'filename', b => 'dir');
my @not_a_file = ('%option a% not a file', a => 'filename');
my @not_a_dir = ('%option a% not a directory', a => 'dir');

with_my_dir "d1/d2", "d1/d2/d3", sub {
	my ($curdir) = @_;

	touch "../myfile1";
	touch "myfile2";
	touch "d3/myfile3";

	fails_file_and_dir "filename inside dir",
		"d3", "myfile2", @filename_inside_dir;

	fails_file_and_dir "filename inside dir",
		"$curdir/d3", "$curdir/myfile2", @filename_inside_dir;

	fails_file_and_dir "filename inside dir",
		"d3", "../myfile1", @filename_inside_dir;

	fails_file_and_dir "filename inside dir",
		".", "../myfile1", @filename_inside_dir;

	fails_file_and_dir "file not found",
		".", "../notafile", @not_a_file, value => '../notafile';

	fails_file_and_dir "file not found",
		"d3", "../notafile", @not_a_file, value => '../notafile';

	fails_file_and_dir "file not found",
		"d3", "notafile", @not_a_file, value => 'notafile';

	fails_file_and_dir "filename inside dir",
		"notadir", "myfile2", @not_a_dir, value => 'notadir';

	fails_file_and_dir "filename inside dir",
		"$curdir/notadir", "$curdir/myfile2", @not_a_dir, value => "$curdir/notadir";

	fails_file_and_dir "filename inside dir",
		"notadir", "notafile", @not_a_dir, value => 'notadir';

	# TODO: test also for bad filename
	fails_file_and_dir "filename inside dir",
		('x' x 2048), "myfile2", '%option a% should be less than 512 characters', a => 'dir', value => ("x" x 2048);

};

SKIP: {
	skip "Cannot run under root", 24 if $^O eq 'cygwin' || is_posix_root; # too britle even under cygwin non-root

	my $restricted_abs = "$mtroot/restricted";
	my $normal_abs = "$restricted_abs/normal";
	my $file_abs = "$normal_abs/file";


	with_my_dir "restricted/normal", "restricted/normal/another", sub {
		touch $file_abs;

		mkpath "top";

		my $file_rel = "file";
		my $normal_rel = "../normal";

		is stat($file_rel)->ino, stat($file_abs)->ino;
		is stat($normal_rel)->ino, stat($normal_abs)->ino;

		ok -f $file_rel;
		ok -f $file_abs;
		ok -d $normal_rel;
		ok -d $normal_rel;


		test_file_and_dir "dir/filename should work",
			"another/..", $file_rel, $file_rel;

		test_file_and_dir "dir/filename should work",
			"$mtroot/restricted/normal", $file_rel, $file_rel;

		chmod 000, $restricted_abs;

		ok  -f $file_rel;
		ok !-f $file_abs;
		ok !-d $normal_rel;
		ok !-d $normal_abs;

		fails_file_and_dir "filename inside dir - dir is unresolvable",
			"another/..", $file_rel, 'cannot_resolve_dir', a => 'dir';

		fails_file_and_dir "filename inside dir - file is unresolvable",
			$mtroot, $file_rel, 'cannot_resolve_file', a => 'filename';

		chmod 700, $restricted_abs;
	}
};

# TODO: also test with non-ascii filenames
with_my_dir "d1", sub {
	touch "myfile";
	touch "unreadable";
	touch "empty", "";

	chmod 000, "unreadable";

	assert_fails_on_filesystem "should check --filename for readability",
		[qw!upload-file --config glacier.cfg --vault myvault --journal j --set-rel-filename somefile!, '--filename', "notafile"],
		[],
		'%option a% not a file', a => 'filename', value => 'notafile';

	assert_fails_on_filesystem "should check --filename for readability",
		[qw!upload-file --config glacier.cfg --vault myvault --journal j --set-rel-filename somefile!, '--filename', "empty"],
		[],
		'%option a% file size is zero', a => 'filename', value => 'empty';

	SKIP: {
		skip "Cannot run under root", 4 if is_posix_root;
		assert_fails_on_filesystem "should check --filename for readability",
			[qw!upload-file --config glacier.cfg --vault myvault --journal j --set-rel-filename somefile!, '--filename', "unreadable"],
			[],
			'%option a% file not readable', a => 'filename', value => 'unreadable';
	}

	assert_passes_on_filesystem "should check --filename for readability",
		[qw!upload-file --config glacier.cfg --vault myvault --journal j --set-rel-filename somefile!, '--filename', "myfile"],
		'name-type' => 'rel-filename',
		'data-type' => 'filename',
		'set-rel-filename' => 'somefile',
		'relfilename' => 'somefile',
		filename => 'myfile',
		'filenames-encoding' => 'UTF-8';
};

1;
