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
use Test::Simple tests => 228;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use File::Path;
use JournalTest;
use open qw/:std :utf8/; # actually, we use "UTF-8" in other places.. UTF-8 is more strict than utf8 (w/out hypen)
use TestUtils;

warning_fatal();


my $mtroot = get_temp_dir();
my $tmproot = "$mtroot/journal-plain";
my $dataroot = "$tmproot/dataL1/dataL2";
my $journal_file = "$tmproot/journal";


rmtree($tmproot) if ($tmproot) && (-d $tmproot);
mkpath($dataroot);


my $testfiles1 = [
{ type => 'dir', filename => 'dirA' },
{ type => 'normalfile', filename => 'dirA/file1', content => 'dAf1a', journal => 'created', mtime => 1357493991 },
{ type => 'normalfile', filename => 'dirA/file2', content => 'dAf2aa', skip=>1},
{ type => 'normalfile', filename => 'dirA/file3', content => 'dAf2aacc', skip=>1, journal=>'created_and_deleted', mtime => -1969112106 },
{ type => 'dir', filename => 'dirB' },
{ type => 'normalfile', filename => 'dirB/file1', content => 'dBf1aaa', skip=>1 , journal => 'created', mtime => -1969112106},
{ type => 'normalfile', filename => 'dirB/file2', content => 'dBf2aaaa' , journal => 'created'},
{ type => 'dir', filename => 'dirB/dirB1' },
{ type => 'normalfile', filename => 'dirB/dirB1/file1', content => 'dB1f1bbbba', skip=>1},
{ type => 'normalfile', filename => 'dirB/dirB1/file2', content => 'dB1f2bbbbaa' , journal => 'created'},

];


for my $jv (qw/0 A B C/) {
	my $J = JournalTest->new(create_journal_version => $jv, mtroot => $mtroot, tmproot => $tmproot, dataroot => $dataroot, journal_file => $journal_file, testfiles => $testfiles1);
	$J->test_all();
}

for my $follow (qw/0 1/) {
	my $J = JournalTest->new(create_journal_version => 'B', follow => 1, mtroot => $mtroot, tmproot => $tmproot, dataroot => $dataroot, journal_file => $journal_file, testfiles => $testfiles1);
	$J->test_all();
}

1;
