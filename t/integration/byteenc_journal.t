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
use Test::More;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use App::MtAws::Utils;
use App::MtAws::Filter;
use File::Path;
use JournalTest;
use Encode;
use File::Temp ();
use open qw/:std :utf8/; # actually, we use "UTF-8" in other places.. UTF-8 is more strict than utf8 (w/out hypen)
use TestUtils;

warning_fatal();

if( $^O =~ /^(linux|.*bsd|solaris)$/i ) {
      plan tests => 2700;
} else {
      plan skip_all => 'Test cannot be performed on character-oriented filesystem';
}
  

binmode Test::More->builder->output, ":utf8";
binmode Test::More->builder->failure_output, ":utf8";

my $TEMP = File::Temp->newdir();
my $mtroot = $TEMP->dirname();
my $tmproot = "$mtroot/журнал-byteenc";
my $dataroot = "$tmproot/dataL1/данныеL2";
my $journal_file = "$tmproot/journal";



# -0.* -фexclude/a/ +*.gz -



my $testfiles1 = [

{ type => 'dir', filename => 'фexclude'  },
{ type => 'dir', filename => 'фexclude/a' },
{ type => 'normalfile', filename => 'фexclude/a/1.gz', content => 'exclude1', journal => 'created', exclude=>1 },
{ type => 'normalfile', filename => 'фexclude/b', content => 'exclude2', journal => 'created', exclude=>0 },
{ type => 'normalfile', filename => 'фexclude/b.gz', content => 'exclude3', journal => 'created', exclude=>0 },
{ type => 'normalfile', filename => 'фexclude/c.gz', content => 'exclude4', journal => 'created', exclude=>0 },
{ type => 'normalfile', filename => 'фexclude/0.gz', content => 'exclude5', journal => 'created', exclude=>1 },
{ type => 'normalfile', filename => 'фexclude/0.txt', content => 'exclude5', exclude=>1 },



{ type => 'dir', filename => 'каталогA' },
{ type => 'normalfile', filename => 'каталогA/file1', content => 'dAf1a', journal => 'created' },
{ type => 'normalfile', filename => 'каталогA/file2', content => 'dAf2aa', skip=>1},
{ type => 'normalfile', filename => 'каталогA/file22', content => 'dAf2aa2'},
{ type => 'normalfile', filename => 'каталогA/file3', content => 'тест1', skip=>1, journal=>'created_and_deleted'},
{ type => 'dir', filename => 'dirB' },
{ type => 'normalfile', filename => 'dirB/file1', content => 'dBf1aaa',skip=>1 , journal => 'created'},
{ type => 'normalfile', filename => 'dirB/file2', content => 'dBf2aaaa' , journal => 'created', mtime => -1969112105 },
{ type => 'dir', filename => 'dirB/dirB1' },
{ type => 'normalfile', filename => 'dirB/dirB1/file1', content => 'тест2', skip=>1},
{ type => 'normalfile', filename => 'dirB/dirB1/file2', content => 'dB1f2bbbbaa' , journal => 'created'},

];

for my $jv (qw/0 A B C/) {
	for my $journal_encoding (qw/UTF-8 KOI8-R CP1251/) {#  # TODO: disable test on Unicode Filesystems (MacOSX)
		for my $filenames_encoding (qw/UTF-8 KOI8-R CP1251/) {# 
			my $tmproot_e = encode($filenames_encoding, $tmproot, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
			my $dataroot_e = encode($filenames_encoding, $dataroot, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
			
			rmtree($tmproot_e) if ($tmproot_e) && (-d $tmproot_e);
			mkpath($dataroot_e);
			
			set_filename_encoding $filenames_encoding;

			my $F = App::MtAws::Filter->new();			
			$F->parse_filters('-0.* -фexclude/a/ +');
			
			#use Data::Dumper;
			#print Dumper $filter;
			
			
			my $J = JournalTest->new(journal_encoding => $journal_encoding, filenames_encoding => $filenames_encoding,
				create_journal_version => $jv, mtroot => $mtroot, tmproot => $tmproot, dataroot => $dataroot,
				journal_file => $journal_file, testfiles => $testfiles1, filter => $F);
			$J->test_all();
			
			rmtree($tmproot_e) if ($tmproot_e) && (-d $tmproot_e);
		}
	}
}


1;
