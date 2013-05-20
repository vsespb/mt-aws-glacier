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
use Test::More tests => 44;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use App::MtAws::Utils;
use App::MtAws::Exceptions;
use Test::MockModule;
use Encode;
use TestUtils;

warning_fatal();

my $relfilename = 'def/abc';
my $rootdir = 'root_dir';
my $data = {
	absfilename => File::Spec->rel2abs($relfilename, $rootdir),
	relfilename => $relfilename
};


# test _can_read_filename_for_mode test
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
		my $anotherfile = 'newfile1';
		$J->{journal_h}->{$relfilename} = $data;
		
		ok( $J->_can_read_filename_for_mode($relfilename, 'all') == 1);
		ok( $J->_can_read_filename_for_mode($anotherfile, 'all') == 1);
		
		ok( $J->_can_read_filename_for_mode($relfilename, 'new') == 0);
		ok( $J->_can_read_filename_for_mode($anotherfile, 'new') == 1);

		ok( $J->_can_read_filename_for_mode($relfilename, 'existing') == 1);
		ok( $J->_can_read_filename_for_mode($anotherfile, 'existing') == 0);
}

# test read_all_files
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
		my @args;
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_read_files', sub { (undef, @args) = @_; return ['fileA']});
		$J->read_all_files();
		
		is_deeply(\@args, ['all']);
		is_deeply($J->{allfiles_a}, ['fileA']);
}

# test read_new_files
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
		my @args;
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_read_files', sub { (undef, @args) = @_; return ['fileB']});
		$J->read_new_files(117);
		
		is_deeply(\@args, ['new',117]);
		is_deeply($J->{newfiles_a}, ['fileB']);
}

# test read_existing_files
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
		my @args;
		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_read_files', sub { (undef, @args) = @_; return ['fileC']});
		$J->read_existing_files();
		
		is_deeply(\@args, ['existing']);
		is_deeply($J->{existingfiles_a}, ['fileC']);
}

# max_number_of_files should be triggered
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		my $maxfiles = 4;
		(my $mock_journal = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_is_file_exists', sub { return 1});

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (map { "$rootdir/$_" } @filelist);
			});
			
		$File::Find::prune = 0;
		my $filelist = $J->_read_files('all', $maxfiles);
		
		my @expected = map { { relfilename => File::Spec->abs2rel($_, $J->{root_dir}) } } map { "$rootdir/$_" }  @filelist[0..$maxfiles-1]; 
		is_deeply($filelist, \@expected);
		ok($maxfiles < scalar @filelist - 1);
		ok($File::Find::prune == 1);
}

# max_number_of_files should not be triggered
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		my $maxfiles = 14;
		(my $mock_journal = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_is_file_exists', sub { return 1});

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (map { "$rootdir/$_" } @filelist);
			});
			
		$File::Find::prune = 1;
		my $filelist = $J->_read_files('all', $maxfiles);
		
		my @expected = map { { relfilename => File::Spec->abs2rel($_, $J->{root_dir}) } } map { "$rootdir/$_" }  @filelist; 
		is_deeply($filelist, \@expected);
		ok($maxfiles >= scalar @filelist - 1);
		ok($File::Find::prune == 0);
}

# max_number_of_files should not be triggered when zero
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		(my $mock_journal = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_is_file_exists', sub { return 1});

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (map { "$rootdir/$_" } @filelist);
			});
			
		$File::Find::prune = 1;
		my $filelist = $J->_read_files('all', 0);
		
		my @expected = map { { relfilename => File::Spec->abs2rel($_, $J->{root_dir}) } } map { "$rootdir/$_" }  @filelist; 
		is_deeply($filelist, \@expected);
		ok($File::Find::prune == 0);
}

# should not add file if it does not exist
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{root_dir/file1 root_dir/file2 root_dir/file3 root_dir/file4 root_dir/file5 root_dir/file6 root_dir/file7};
		(my $mock_journal = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_is_file_exists', sub { return 0 });

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (@filelist);
			});
			
		my $filelist = $J->_read_files('all', 0);
		is_deeply($filelist, []);
}

# should catch broken UTF-8 in filename
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my $brokenname = "\xD1\xD2";
		ok ! defined eval { decode("UTF-8", $brokenname, Encode::FB_CROAK|Encode::LEAVE_SRC) }, "our UTF example should be broken";
		my @filelist = ($brokenname);
		
		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (@filelist);
			});
		
		ok ! defined eval { $J->_read_files('all', 0); 1; };
		is get_exception->{code}, 'invalid_octets_filename';
		is get_exception->{filename}, hex_dump_string($brokenname);
		is get_exception->{enc}, "UTF-8";
		ok exception_message(get_exception) =~ /Invalid octets in filename, does not map to desired encoding/i;
}

# should catch TAB,CR,LF in filename
for my $brokenname ("ab\tc", "some\nfile", "some\rfile") {
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = ($brokenname);
		
		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (@filelist);
			});
		
		ok ! defined eval { $J->_read_files('all', 0); 1; };
		is get_exception->{filename}, hex_dump_string($brokenname);
		is get_exception->{code}, 'invalid_chars_filename';
		ok exception_message(get_exception) =~ /Not allowed characters in filename/i;
}

# should not add file _can_read_filename_for_mode returns false
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{root_dir/file1 root_dir/file2 root_dir/file3 root_dir/file4 root_dir/file5 root_dir/file6 root_dir/file7};
		my $mock_journal = Test::MockModule->new('App::MtAws::Journal');
		$mock_journal->mock('_is_file_exists', sub { return 1 });
		$mock_journal->mock('_can_read_filename_for_mode', sub { return 0 });
		
		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (@filelist);
			});
			
		my $filelist = $J->_read_files('all', 0);
		is_deeply($filelist, []);
}

# should pass correct options to find
{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		my $mock_journal = Test::MockModule->new('App::MtAws::Journal');
		$mock_journal->mock('_is_file_exists', sub { return 1 });
		
		my ($args, $root_dir);
		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				($args, $root_dir) = @_;
				$args->{wanted}->() for (map { "$rootdir/$_" } @filelist);
			});
			
		my $filelist = $J->_read_files('all', 0);
		ok($args->{no_chdir} == 1);
		ok($root_dir eq $rootdir);
		ok(defined($args->{wanted}));
		ok(!defined($args->{preprocess}));
}

# preprocess sub should decode to utf8
# should call _can_read_filename_for_mode

1;
