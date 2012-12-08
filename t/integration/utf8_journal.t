#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::Simple tests => 76;
use lib qw/../;
use Journal;
use File::Path;
use JournalTest;
use open qw/:std :utf8/; # actually, we use "UTF-8" in other places.. UTF-8 is more strict than utf8 (w/out hypen)

binmode Test::Simple->builder->output, ":utf8";
binmode Test::Simple->builder->failure_output, ":utf8";

my $mtroot = '/tmp/mt-aws-glacier-tests';
my $tmproot = "$mtroot/журнал-1";
my $dataroot = "$tmproot/dataL1/данныеL2";
my $journal_file = "$tmproot/journal";



rmtree($tmproot) if ($tmproot) && (-d $tmproot);
mkpath($dataroot);


my $testfiles1 = [
{ type => 'dir', filename => 'каталогA' },
{ type => 'normalfile', filename => 'каталогA/file1', content => 'dAf1a', journal => 'created' },
{ type => 'normalfile', filename => 'каталогA/file2', content => 'dAf2aa', skip=>1},
{ type => 'normalfile', filename => 'каталогA/file3', content => 'тест1', skip=>1, journal=>'created_and_deleted'},
{ type => 'dir', filename => 'dirB' },
{ type => 'normalfile', filename => 'dirB/file1', content => 'dBf1aaa',skip=>1 , journal => 'created'},
{ type => 'normalfile', filename => 'dirB/file2', content => 'dBf2aaaa' , journal => 'created'},
{ type => 'dir', filename => 'dirB/dirB1' },
{ type => 'normalfile', filename => 'dirB/dirB1/file1', content => 'тест2', skip=>1},
{ type => 'normalfile', filename => 'dirB/dirB1/file2', content => 'dB1f2bbbbaa' , journal => 'created'},

];

for my $jv (qw/0 A/) {
	my $J = JournalTest->new(create_journal_version => $jv, mtroot => $mtroot, tmproot => $tmproot, dataroot => $dataroot, journal_file => $journal_file, testfiles => $testfiles1);
	$J->test_all();
}

1;
