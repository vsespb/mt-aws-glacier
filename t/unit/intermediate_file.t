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
use Test::More tests => 53;
use FindBin;
use Carp;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use Data::Dumper;
use TestUtils;
use App::MtAws::IntermediateFile;
use File::stat;

my $TEMP = File::Temp->newdir();
my $rootdir = $TEMP->dirname();

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
	ok ! defined eval { App::MtAws::IntermediateFile->new(); 1; }, "should confess without dir";
}

{
	my $I = bless {}, 'App::MtAws::IntermediateFile';
	ok ! defined eval { $I->filename; 1 }, "should confess if filename missing";
}

{
	my $I = App::MtAws::IntermediateFile->new(dir => $rootdir);
	my $filename = $I->filename;
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
	my $I = App::MtAws::IntermediateFile->new(dir => $rootdir);
	my $filename = $I->filename;
	ok -f $filename, "should create temp file";
	ok -e $filename, "file exists";

	ok open(my $f, ">", $filename), "open should work";
	my $data_sample = "abcdefxyz\n";
	print $f $data_sample;
	ok close($f), "close should work";

	my $permanent_name = "$rootdir/permanent_file1";
	ok ! -e $permanent_name, "assume permanent file not yet exists";
	$I->make_permanent($permanent_name);

	is ( (stat($permanent_name)->mode & 07777), (0666 & ~umask), "file should have default permissions");
	is slurp($permanent_name), $data_sample, "data should be readable";
}

{
	my $I = App::MtAws::IntermediateFile->new(dir => $rootdir);
	my $filename = $I->filename;
	ok -f $filename, "should create temp file";

	my $permanent_name = "$rootdir/permanent_file3";
	ok ! -e $permanent_name, "assume permanent file not yet exists";
	$I->make_permanent($permanent_name);
	ok ! defined eval { $I->make_permanent($permanent_name."x"); 1; }, "should confess if make_permanent called twice";
	like $@, qr/file already permanent or not initialized/, "should confess with right message if make_permanent called twice";

}

{
	ok ! -e do {
		my $I = App::MtAws::IntermediateFile->new(dir => $rootdir);
		my $filename = $I->filename;
		ok -f $filename, "should create temp file";
		$filename;
	}, "file auto-removed";
}

for (['a'], ['b','c'], ['b', 'c', 'd'], ['e', 'f', 'g']) {
	my $subdir = join('/', @$_);
	my $fulldir = "$rootdir/$subdir";
	my $I = App::MtAws::IntermediateFile->new(dir => $fulldir);
	my $filename = $I->filename;
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
		my $I = App::MtAws::IntermediateFile->new(dir => $rootdir);
		my $filename = $I->filename;
		ok -f $filename, "should create temp file";
		my $permanent_name = "$rootdir/permanent_file";
		ok ! -e $permanent_name, "assume permanent file not yet exists";
		$I->make_permanent($permanent_name);
		ok ! -e $filename, "temp file is gone";
		ok -f $permanent_name, "file moved to permanent location";
		$permanent_name;
	}, "permanent file not discarded";

}


# TODO: test with fork (twice)
# TODO: test it throws exceptions (like perms errors)
# TODO: binaryfilenames stuff

1;

