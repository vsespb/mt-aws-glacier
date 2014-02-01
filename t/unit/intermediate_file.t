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
use Test::More tests => 109;
use FindBin;
use Carp;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use Data::Dumper;
use TestUtils;
use App::MtAws::IntermediateFile;
use App::MtAws::Exceptions;
use File::stat;
use File::Path;
use Encode;
use App::MtAws::Utils;

my $rootdir = get_temp_dir();

warning_fatal();

sub slurp
{
	open(my $f, "<", shift) or confess;
	my $got_data = do { local $/; <$f> };
	close $f;
	return $got_data;
}

sub test_read_write
{
	my ($filename) = @_;
	ok open(my $f, ">", $filename), "open should work";
	my $data_sample = "abcdef\n";
	print $f $data_sample;
	ok close($f), "close should work";
	is slurp($filename), $data_sample, "data should be readable";
}

{
	ok ! defined eval { App::MtAws::IntermediateFile->new(); 1; }, "should confess without target_file";
}

{
	no warnings 'redefine';
	local *App::MtAws::IntermediateFile::_init = sub {};
	ok ! defined eval { App::MtAws::IntermediateFile->new(target_file => 123, dir => 456); 1; }, "should confess with extra arguments";
}

{
	no warnings 'redefine';
	local *App::MtAws::IntermediateFile::_init = sub {};
	my $r = App::MtAws::IntermediateFile->new(target_file => 0);
	ok "should work when target_file is FALSE";
	is $r->{_init_pid}, $$, "should init init_pid";
}

{
	my $I = bless {}, 'App::MtAws::IntermediateFile';
	ok ! defined eval { $I->tempfilename; 1 }, "should confess if filename missing";
}

{
	my $I = bless {}, 'App::MtAws::IntermediateFile';
	ok ! defined eval { $I->make_permanent(1); 1 }, "should confess if extra args provided";
	like $@, qr/unknown arguments/, "should confess with right message";
}

{
	my $I = App::MtAws::IntermediateFile->new(target_file => "$rootdir/target1");
	my $filename = $I->tempfilename;
	ok -f $filename, "should create temp file";
	ok -e $filename, "file exists";
	my $perms = stat($filename)->mode & 07777;
	is $perms & 0077, 0, "file should not be world accessible";
	ok $perms & 0400, "file should be readable";
	ok $perms & 0200, "file should be writable";
	ok $filename =~ /__mtglacier_temp/, 'file should have __mtglacier_temp in name';
	ok $filename =~ /\.tmp$/, 'file should end with .tmp extension';
	ok $filename =~ /$$/, 'file should contain PID';
	ok $filename =~ /^\Q$rootdir\E\/__mtglacier_temp/, "file should be inside supplied directory";
	ok open(my $f, ">", $filename), "open should work";
	my $data_sample = "abcdef\n";
	print $f $data_sample;
	ok close($f), "close should work";
	is slurp($filename), $data_sample, "data should be readable";
}

{
	my $permanent_name = "$rootdir/permanent_file1";
	my $I = App::MtAws::IntermediateFile->new(target_file => $permanent_name);
	my $filename = $I->tempfilename;
	ok -f $filename, "should create temp file";
	ok -e $filename, "file exists";

	ok open(my $f, ">", $filename), "open should work";
	my $data_sample = "abcdefxyz\n";
	print $f $data_sample;
	ok close($f), "close should work";

	ok ! -e $permanent_name, "assume permanent file not yet exists";
	$I->make_permanent;

	is ( (stat($permanent_name)->mode & 07777), (0666 & ~umask), "file should have default permissions");
	is slurp($permanent_name), $data_sample, "data should be readable";
}

{
	my $permanent_name = "$rootdir/permanent_file2";
	my $I = App::MtAws::IntermediateFile->new(target_file => $permanent_name, mtime => 1234567);
	my $filename = $I->tempfilename;
	ok -f $filename, "should create temp file";
	ok -e $filename, "file exists";
	ok ! -e $permanent_name, "assume permanent file not yet exists";
	$I->make_permanent;

	is stat($permanent_name)->mtime, 1234567, "it should set mtime";
}

{
	my $permanent_name = "$rootdir/permanent_file4";
	my $I = App::MtAws::IntermediateFile->new(target_file => $permanent_name, mtime => undef);
	my $filename = $I->tempfilename;
	ok -f $filename, "should create temp file";
	ok -e $filename, "file exists";
	ok ! -e $permanent_name, "assume permanent file not yet exists";
	my $saved_mtime = stat($filename)->mtime;
	$I->make_permanent;

	is stat($permanent_name)->mtime, $saved_mtime, "it should work with mtime=undef";
}

{
	my $permanent_name = "$rootdir/permanent_file3";
	my $I = App::MtAws::IntermediateFile->new(target_file => $permanent_name);
	my $filename = $I->tempfilename;
	ok -f $filename, "should create temp file";

	ok ! -e $permanent_name, "assume permanent file not yet exists";
	$I->make_permanent;
	ok ! defined eval { $I->make_permanent; 1; }, "should confess if make_permanent called twice";
	like $@, qr/file already permanent or not initialized/, "should confess with right message if make_permanent called twice";

}

{
	ok ! -e do {
		my $I = App::MtAws::IntermediateFile->new(target_file => "$rootdir/something_not_existant");
		my $filename = $I->tempfilename;
		ok -f $filename, "should create temp file";
		$filename;
	}, "file auto-removed";
}

for (['a'], ['b','c'], ['b', 'c', 'd'], ['e', 'f', 'g']) {
	my $subdir = join('/', @$_);
	my $fulldir = "$rootdir/$subdir";
	my $perm_file = "$fulldir/permfile";
	my $I = App::MtAws::IntermediateFile->new(target_file => $perm_file);
	my $filename = $I->tempfilename;
	ok -f $filename, "should create temp file and several subdirs: $subdir";
	ok -d $fulldir, "just checking that directory is directory";

	my $trydir = '';
	for my $part (@$_) {
		$trydir .= '/' . $part;
		is ( (stat("$rootdir$trydir")->mode & 07777), (0777 & ~umask), "directory $trydir should have default permissions");
	}
	is $trydir, "/$subdir", "assume tested directories calculated correctly";
}

{
	ok -f do {
		my $permanent_name = "$rootdir/permanent_file";
		my $I = App::MtAws::IntermediateFile->new(target_file => $permanent_name);
		my $filename = $I->tempfilename;
		ok -f $filename, "should create temp file";
		ok ! -e $permanent_name, "assume permanent file not yet exists";
		$I->make_permanent;
		ok ! -e $filename, "temp file is gone";
		ok -f $permanent_name, "file moved to permanent location";
		$permanent_name;
	}, "permanent file not discarded";

}

SKIP: {
	skip "Cannot run under root", 5 if is_posix_root;
	my $dir = "$rootdir/denied1";
	ok mkpath($dir), "path is created";
	ok -d $dir, "path is created";;
	chmod 0444, $dir;
	ok ! defined eval { App::MtAws::IntermediateFile->new(target_file => "$dir/somefile"); 1 }, "File::Temp should throw exception";
	is get_exception->{code}, 'cannot_create_tempfile', "File::Temp correct code for exception";
	is get_exception->{dir}, $dir, "File::Temp correct dir for exception";
}

SKIP: {
	skip "Cannot run under root", 5 if is_posix_root;
	my $dir = "$rootdir/denied2";
	ok mkpath($dir), "path is created";
	ok -d $dir, "path is created";;
	chmod 0444, $dir;
	ok ! defined eval { App::MtAws::IntermediateFile->new(target_file => "$dir/b/c/somefile"); 1 }, "mkpath() should throw exception";
	is get_exception->{code}, 'cannot_create_directory', "mkpath correct code for exception";
	is get_exception->{dir}, "$dir/b/c", "mkpath correct dir for exception";
}

SKIP: {
	skip "Cannot run under root", 7 if is_posix_root;
	my $dir = "$rootdir/testpermanent";
	ok ! -e $dir, "not yet exists";
	ok mkpath($dir), "path is created";
	ok -d $dir, "path is created";
	my $dest = "$dir/dest";
	mkdir "$dir/dest";
	my $I = App::MtAws::IntermediateFile->new(target_file => $dest);
	my $tmpfile = $I->tempfilename;
	ok ! defined eval { $I->make_permanent; 1 }, "should throw exception if cant rename files";
	is get_exception->{code}, 'cannot_rename_file', "correct exception code";
	is get_exception->{from}, $tmpfile, "correct exception 'from'";
	is get_exception->{to}, $dest, "correct exception 'to'";
}

{
	is get_filename_encoding, 'UTF-8', "assume utf8 encoding is set";
	my $dir = "$rootdir/тест2";
	my $I = App::MtAws::IntermediateFile->new(target_file => "$dir/somefile");
	like $I->tempfilename, qr/\Q$dir\E/, "filename should contain directory name, thus be in UTF8";
	ok -d $dir, "dir in UTF-8 should not exist";
}

SKIP: {
	skip "Test cannot be performed on character-oriented filesystem", 5 unless can_work_with_non_utf8_files;
	local $App::MtAws::Utils::_filename_encoding = 'KOI8-R';
	is get_filename_encoding, 'KOI8-R', "assume encoding is set";
	my $dir = "$rootdir/тест1";
	my $koidir = encode("KOI8-R", $dir);
	my $I = App::MtAws::IntermediateFile->new(target_file => "$dir/somefile");
	like $I->tempfilename, qr/\Q$dir\E/, "filename should contain directory name, thus be in UTF8";
	unlike $I->tempfilename, qr/\Q$koidir\E/, "filename should not contain KOI8-R directory name";
	ok ! -d $dir, "dir in UTF-8 should not exist";
	ok -d $koidir, "dir in KOI8-R should exist";
}

SKIP: {
	skip "Test cannot be performed on character-oriented filesystem", 7 unless can_work_with_non_utf8_files;
	local $App::MtAws::Utils::_filename_encoding = 'KOI8-R';
	is get_filename_encoding, 'KOI8-R', "assume encoding is set";
	my $dir = "$rootdir/test_permanent_and_encoding";
	my $perm_file = "$rootdir/test_permanent_and_encoding_файл";
	my $koi_perm_file = encode("KOI8-R", $perm_file);
	ok ! -e $dir, "dir does not exist";
	ok ! -e $perm_file, "perm_file in UTF8 does not exist";
	ok ! -e $koi_perm_file, "perm_file in KOI8-R does not exist";
	my $I = App::MtAws::IntermediateFile->new(target_file => $perm_file, mtime => 1234567);
	$I->make_permanent;
	ok ! -e $perm_file, "perm_file in UTF8 does not exist";
	ok -e $koi_perm_file, "perm_file in KOI8-R exists";
	is stat($koi_perm_file)->mtime, 1234567, "it should set mtime";
}

SKIP: {
	for (5) {
		skip "Test cannot be performed on character-oriented filesystem", $_ unless can_work_with_non_utf8_files;
		skip "Cannot run under root", $_ if is_posix_root;
	}
	local $App::MtAws::Utils::_filename_encoding = 'KOI8-R';
	is get_filename_encoding, 'KOI8-R', "assume encoding is set";
	my $basedir = "$rootdir/base1";
	ok ! -e $basedir, "basedir not yet exists";
	ok mkpath($basedir), "basedir created";
	chmod 0444, $basedir;
	my $dir = "$basedir/тест1";
	my $koidir = encode("KOI8-R", $dir);
	ok ! defined eval { App::MtAws::IntermediateFile->new(target_file => "$dir/somefile"); 1 }, "should fail with exception";
	my $msg = exception_message(get_exception);
	$msg =~ s/[[:ascii:]]//g;
	like $msg, qr/^(тест)+$/, "the only non-ascii characters should be utf name";
}

SKIP: {
	for (6) {
		skip "Test cannot be performed on character-oriented filesystem", $_ unless can_work_with_non_utf8_files;
		skip "Cannot run under root", $_ if is_posix_root;
	}
	local $App::MtAws::Utils::_filename_encoding = 'KOI8-R';
	is get_filename_encoding, 'KOI8-R', "assume encoding is set";
	my $basedir = "$rootdir/тест42";
	my $koidir = encode("KOI8-R", $basedir);
	ok ! -e $koidir, "basedir not yet exists";
	ok mkpath($koidir), "basedir created";
	ok chmod(0444, $koidir), "permissions 0444 ok";
	ok ! defined eval { App::MtAws::IntermediateFile->new(target_file => "$basedir/somefile"); 1 }, "should fail with exception";
	my $msg = exception_message(get_exception);
	$msg =~ s/[[:ascii:]]//g;
	like $msg, qr/^(тест)+$/, "the only non-ascii characters should be utf name";
}


1;
