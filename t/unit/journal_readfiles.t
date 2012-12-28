#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 26;
use Test::Deep;
use lib qw{.. ../..};
use Journal;
use Test::MockModule;

my $relfilename = 'def/abc';
my $rootdir = 'root_dir';
my $data = {
	absfilename => File::Spec->rel2abs($relfilename, $rootdir),
	relfilename => $relfilename
};


# test _can_read_filename_for_mode test
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);
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
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);
		my @args;
		(my $mock = Test::MockModule->new('Journal'))->
			mock('_read_files', sub { (undef, @args) = @_; return ['fileA']});
		$J->read_all_files();
		
		is_deeply(\@args, ['all']);
		is_deeply($J->{allfiles_a}, ['fileA']);
}

# test read_new_files
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);
		my @args;
		(my $mock = Test::MockModule->new('Journal'))->
			mock('_read_files', sub { (undef, @args) = @_; return ['fileB']});
		$J->read_new_files(117);
		
		is_deeply(\@args, ['new',117]);
		is_deeply($J->{newfiles_a}, ['fileB']);
}

# test read_existing_files
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);
		my @args;
		(my $mock = Test::MockModule->new('Journal'))->
			mock('_read_files', sub { (undef, @args) = @_; return ['fileC']});
		$J->read_existing_files();
		
		is_deeply(\@args, ['existing']);
		is_deeply($J->{existingfiles_a}, ['fileC']);
}

# max_number_of_files should be triggered
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		my $maxfiles = 4;
		(my $mock_journal = Test::MockModule->new('Journal'))->
			mock('_is_file_exists', sub { return 1});

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (map { "$rootdir/$_" } @filelist);
			});
			
		$File::Find::prune = 0;
		my $filelist = $J->_read_files('all', $maxfiles);
		
		my @expected = map { { absfilename => $_, relfilename => File::Spec->abs2rel($_, $J->{root_dir}) } } map { "$rootdir/$_" }  @filelist[0..$maxfiles-1]; 
		is_deeply($filelist, \@expected);
		ok($maxfiles < scalar @filelist - 1);
		ok($File::Find::prune == 1);
}

# max_number_of_files should not be triggered
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		my $maxfiles = 14;
		(my $mock_journal = Test::MockModule->new('Journal'))->
			mock('_is_file_exists', sub { return 1});

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (map { "$rootdir/$_" } @filelist);
			});
			
		$File::Find::prune = 1;
		my $filelist = $J->_read_files('all', $maxfiles);
		
		my @expected = map { { absfilename => $_, relfilename => File::Spec->abs2rel($_, $J->{root_dir}) } } map { "$rootdir/$_" }  @filelist; 
		is_deeply($filelist, \@expected);
		ok($maxfiles >= scalar @filelist - 1);
		ok($File::Find::prune == 0);
}

# max_number_of_files should not be triggered when zero
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		(my $mock_journal = Test::MockModule->new('Journal'))->
			mock('_is_file_exists', sub { return 1});

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (map { "$rootdir/$_" } @filelist);
			});
			
		$File::Find::prune = 1;
		my $filelist = $J->_read_files('all', 0);
		
		my @expected = map { { absfilename => $_, relfilename => File::Spec->abs2rel($_, $J->{root_dir}) } } map { "$rootdir/$_" }  @filelist; 
		is_deeply($filelist, \@expected);
		ok($File::Find::prune == 0);
}

# should not add file if it does not exist
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		(my $mock_journal = Test::MockModule->new('Journal'))->
			mock('_is_file_exists', sub { return 0 });

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (@filelist);
			});
			
		my $filelist = $J->_read_files('all', 0);
		is_deeply($filelist, []);
}

# should not add file _can_read_filename_for_mode returns false
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		my $mock_journal = Test::MockModule->new('Journal');
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
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};
		my $mock_journal = Test::MockModule->new('Journal');
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
		ok(defined($args->{preprocess}));
}

# preprocess sub should decode to utf8
# should call _can_read_filename_for_mode

1;
