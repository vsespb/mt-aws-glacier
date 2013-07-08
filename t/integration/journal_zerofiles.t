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
use Test::More tests => 12;
use Carp;
use Data::Dumper;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use TestUtils;
use File::Temp ();
use File::Path;

warning_fatal();

my $TEMP = File::Temp->newdir();
my $mtroot = $TEMP->dirname();
my $journal = "$mtroot/journal";
my $rootdir = "$mtroot/root";
mkpath($mtroot);

my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
my $filecount = scalar @filelist;


for my $size (0, 1) {
	for my $is_exist (0, 1) {
		unlink $journal;
		rmtree $rootdir;
		mkpath($rootdir);

		# create journal
		{
			my $J = App::MtAws::Journal->new(journal_file=> $journal, root_dir => $rootdir);
			$J->read_journal(should_exist => 0);
			$J->open_for_write;
			if ($is_exist) {
				$J->add_entry({type => 'CREATED', time => 123, archive_id => ('x' x 100).$_, size => 123, mtime => 123, treehash => 'abc', relfilename => $_})
					for (@filelist)
			}
			$J->close_for_write;
		}

		my $J = App::MtAws::Journal->new(journal_file=> $journal, root_dir => $rootdir);
		$J->read_journal(should_exist => 1);

		touch("$rootdir/$_", $size) for (@filelist);
		$J->read_files({new=>1, existing=>1, missing=>1});

		if ($size) {
			if ($is_exist) {
				assert_listing($J, 0, $filecount, 0);
			} else {
				assert_listing($J, $filecount, 0, 0);
			}
		} else {
			if ($is_exist) {
				assert_listing($J, 0, 0, $filecount);
			} else {
				assert_listing($J, 0, 0, 0);
			}

		}

	}

}

sub assert_listing
{
	my ($J, $new, $existing, $missing) = @_;
	is @{ $J->{listing}{new} }, $new;
	is @{ $J->{listing}{existing} }, $existing;
	is @{ $J->{listing}{missing} }, $missing;
}

sub touch
{
	my ($filename, $content) = @_;
	open(my $f, ">", $filename) or confess "cant write to filename $filename $!";
	print $f $content if $content;
	close $f;
}

