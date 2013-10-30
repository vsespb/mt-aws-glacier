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
use Test::More tests => 12;
use Test::Deep;
use Carp;
use Data::Dumper;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::Journal;
use TestUtils;
use File::Path;

warning_fatal();

my $mtroot = get_temp_dir();
my $journal = "$mtroot/journal";
my $rootdir = "$mtroot/root";
my $hiddendir = "$mtroot/hidden";
mkpath($mtroot);

our $leaf_opt = undef;

sub touch
{
	my ($filename) = @_;
	open(my $f, ">", $filename) or confess "cant write to filename $filename $!";
	print $f "1";
	close $f;
}

sub read_listing
{
	my $J = App::MtAws::Journal->new(journal_file=> $journal, root_dir => $rootdir, follow => 1, leaf_optimization => $leaf_opt);
	$J->read_journal(should_exist => 0);
	$J->read_files({new=>1});
	sort map { $_->{relfilename} } @{ $J->{listing}{new} };
}

sub test_case
{
	rmtree $mtroot;
	mkpath $mtroot;
	mkpath $rootdir;
	mkpath $hiddendir;
	shift->();
	rmtree $mtroot;
}

for $leaf_opt (0, 1) {

	test_case sub {
		mkdir "$rootdir/somedir";
		mkdir "$hiddendir/hdir";
		touch "$hiddendir/hdir/hfile";
		symlink "$hiddendir/hdir", "$rootdir/somedir2" or die;
		cmp_deeply [read_listing], [ qw!somedir2/hfile! ], "should walk symlinked dirs";
	};

	test_case sub {
		mkdir "$rootdir/somedir";
		mkdir "$hiddendir/hdir";
		mkdir "$hiddendir/hdir/A";
		touch "$hiddendir/hdir/A/hfile";
		symlink "$hiddendir/hdir", "$rootdir/somedir2" or die;
		cmp_deeply [read_listing], [ qw!somedir2/A/hfile! ], "should walk symlinked dirs deeper";
	};


	test_case sub {
		mkdir "$rootdir/somedir";
		touch "$rootdir/somedir/file1";
		symlink "$rootdir/somedir/", "$rootdir/somedir/cycle1" or die;
		cmp_deeply [read_listing], [ qw!somedir/file1! ], "should workaround cycle and report one file";
	};

	test_case sub {
		mkdir "$rootdir/somedir";
		touch "$rootdir/somedir/file1";
		touch "$rootdir/somedir/file2";
		symlink "$rootdir/somedir/", "$rootdir/somedir/cycle1" or die;
		cmp_deeply [read_listing], [ sort qw!somedir/file1 somedir/file2! ], "should workaround cycle and report two files";
	};

	test_case sub {
		mkdir "$rootdir/somedir";
		touch "$rootdir/somedir/file1";
		touch "$rootdir/somedir/file2";
		symlink "$rootdir/somedir/file2", "$rootdir/somedir/file2a" or die;

		cmp_deeply [read_listing], [ sort qw!somedir/file1 somedir/file2 somedir/file2a! ], "should report same file twice just like file-find without follow";
	};

	test_case sub {
		mkdir "$rootdir/somedir";
		touch "$rootdir/somedir/file1";
		touch "$rootdir/somedir/file2";
		symlink "$rootdir/somedir/file2", "$rootdir/somedir/file2a" or die;
		unlink "$rootdir/somedir/file2";
		cmp_deeply [read_listing], [ sort qw!somedir/file1! ], "should ignore dangling symlink";
	};

}
