#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::Simple tests => 86;
use lib qw/../;
use Journal;
use File::Path;
use JournalTest;
use open qw/:std :utf8/; # actually, we use "UTF-8" in other places.. UTF-8 is more strict than utf8 (w/out hypen)


my $mtroot = '/tmp/mt-aws-glacier-tests';
my $tmproot = "$mtroot/journal-1";
my $dataroot = "$tmproot/dataL1/dataL2";
my $journal_file = "$tmproot/journal";


rmtree($tmproot) if ($tmproot) && (-d $tmproot);
mkpath($dataroot);


my $testfiles1 = [
{ type => 'dir', filename => 'dirA' },
{ type => 'normalfile', filename => 'dirA/file1', content => 'dAf1a', journal => 'created' },
{ type => 'normalfile', filename => 'dirA/file2', content => 'dAf2aa', skip=>1},
{ type => 'dir', filename => 'dirB' },
{ type => 'normalfile', filename => 'dirB/file1', content => 'dBf1aaa',skip=>1 , journal => 'created'},
{ type => 'normalfile', filename => 'dirB/file2', content => 'dBf2aaaa' , journal => 'created'},
{ type => 'dir', filename => 'dirB/dirB1' },
{ type => 'normalfile', filename => 'dirB/dirB1/file1', content => 'dB1f1bbbba', skip=>1},
{ type => 'normalfile', filename => 'dirB/dirB1/file2', content => 'dB1f2bbbbaa' , journal => 'created'},

];


for my $jv (qw/0 A/) {
	my $J = JournalTest->new(create_journal_version => $jv, mtroot => $mtroot, tmproot => $tmproot, dataroot => $dataroot, journal_file => $journal_file, testfiles => $testfiles1);
	$J->test_all();
}

1;
