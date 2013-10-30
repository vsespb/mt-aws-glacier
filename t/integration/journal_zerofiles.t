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
use Test::More tests => 36;
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
mkpath($mtroot);

sub assert_listing
{
	my ($J, $new, $existing, $missing, $message) = @_;
	is @{ $J->{listing}{new} }, $new, $message;
	is @{ $J->{listing}{existing} }, $existing, $message;
	is @{ $J->{listing}{missing} }, $missing, $message;
}

sub touch
{
	my ($filename, $content) = @_;
	open(my $f, ">", $filename) or confess "cant write to filename $filename $!";
	print $f $content if $content;
	close $f;
}

sub create_journal
{
	my $J = App::MtAws::Journal->new(journal_file=> $journal, root_dir => $rootdir);
	$J->read_journal(should_exist => 0);
	$J->open_for_write;
	$J->add_entry({type => 'CREATED', time => 123, archive_id => ('x' x 100).$_, size => 123, mtime => 123, treehash => 'abc', relfilename => $_})
		for (@_);
	$J->close_for_write;
	$J;
}

my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
my $filecount = scalar @filelist;


for my $included (0, 1) {
	for my $size (undef, 0, 1) {
		for my $exists_in_journal (0, 1) {
			unlink $journal;
			rmtree $rootdir;
			mkpath($rootdir);

			create_journal($exists_in_journal ? @filelist : ());

			my $F = App::MtAws::Filter->new();
			$F->parse_filters($included ? '+file? -' : '-file? +');
			my $J = App::MtAws::Journal->new(journal_file=> $journal, root_dir => $rootdir, filter => $F);
			$J->read_journal(should_exist => 1);

			if (defined $size) {
				touch("$rootdir/$_", $size) for (@filelist);
			}
			$J->read_files({new=>1, existing=>1, missing=>1});

			if ($included) {
				if ($size) {
					if ($exists_in_journal) {
						assert_listing($J, 0, $filecount, 0, "non-zero files which exist in journal");
					} else {
						assert_listing($J, $filecount, 0, 0, "non-zero files which are not in journal");
					}
				} else {
					if ($exists_in_journal) {
						assert_listing($J, 0, 0, $filecount, "zero files which exist in journal");
					} else {
						assert_listing($J, 0, 0, 0, "zero files which are not in journal");
					}

				}
			} else {
				assert_listing($J, 0, 0, 0,  "files denied by filter");
			}

		}
	}
}

