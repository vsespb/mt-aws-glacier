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
use Test::More tests => 127;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use App::MtAws::Utils;
use App::MtAws::Exceptions;
use Test::MockModule;
use Encode;
use List::Util qw/min/;
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

	is( $J->_can_read_filename_for_mode($relfilename, {new=>1, existing=>1}), 'existing');
	is( $J->_can_read_filename_for_mode($relfilename, {existing=>1}), 'existing');
	ok( ! $J->_can_read_filename_for_mode($relfilename, {new=>1}) );
	ok( !$J->_can_read_filename_for_mode($relfilename, {}));

	is( $J->_can_read_filename_for_mode($anotherfile, {new=>1, existing=>1}), 'new');
	is( $J->_can_read_filename_for_mode($anotherfile, {new=>1}), 'new');
	ok( !$J->_can_read_filename_for_mode($anotherfile, {existing=>1}));
	ok( !$J->_can_read_filename_for_mode($anotherfile, {}));
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
			$args->{wanted}->() for (map "$rootdir/$_", @filelist);
		});

	$File::Find::prune = 0;
	$J->read_files({new=>1, existing=>1}, $maxfiles);

	my $expected = { missing => [], existing=>[], new => [map { relfilename => File::Spec->abs2rel($_, $J->{root_dir}) }, map "$rootdir/$_", @filelist[0..$maxfiles-1]]};
	cmp_deeply($J->{listing}, $expected);
	ok($maxfiles < scalar @filelist - 1);
	ok($File::Find::prune == 1);
}

# leaf optimization should work
for my $leaf_opt (0, 1) {
	my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, leaf_optimization => $leaf_opt);

	my @filelist = qw{file1 file2 file3 file4 file5 file6 file7};

	my $got_dont_use_nlink;
	(my $mock_find = Test::MockModule->new('File::Find'))->
		mock('find', sub {
			$got_dont_use_nlink = $File::Find::dont_use_nlink;
		});

	$J->read_files({new=>1, existing=>1});

	cmp_deeply $got_dont_use_nlink, bool(!$leaf_opt), "leaf_optimization should work";
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
			$args->{wanted}->() for (map "$rootdir/$_", @filelist);
		});

	$File::Find::prune = 1;
	$J->read_files({new=>1, existing=>1}, $maxfiles);

	my $expected = { missing => [], existing => [], new => [map { relfilename => File::Spec->abs2rel($_, $J->{root_dir}) }, map "$rootdir/$_", @filelist]};
	cmp_deeply($J->{listing}, $expected);
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
			$args->{wanted}->() for (map "$rootdir/$_", @filelist);
		});

	$File::Find::prune = 1;
	$J->read_files({new=>1, existing=>1}, 0);

	my $expected = { missing => [], existing => [], new => [map { relfilename => File::Spec->abs2rel($_, $J->{root_dir}) }, map "$rootdir/$_",  @filelist] };
	cmp_deeply($J->{listing}, $expected);
	ok($File::Find::prune == 0);
}

# max_number_of_files should be triggered with missing files
for my $missing_mode (qw/0 1/) {
	for my $n (0..4) {
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my @existing = qw{file2 file3 file4};
		my @missing = qw{fileA fileB fileC};
		my @new = qw{file1 file5 file6 file7};

		$J->{journal_h} = { map { $_ => { relfilename => $_ } } (@existing, @missing) };
		my $maxfiles = scalar @existing + (scalar @new) + $n;
		my $n_or_files = min $n, scalar @missing;
		$n_or_files = 0 unless $missing_mode;

		(my $mock_journal = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_is_file_exists', sub {  $_[1] =~ /file\d$/ });

		(my $mock_find = Test::MockModule->new('File::Find'))->
			mock('find', sub {
				my ($args) = @_;
				$args->{wanted}->() for (map "$rootdir/$_", (@new, @existing));
			});

		$File::Find::prune = 0;
		$J->read_files({new=>1, existing=>1, missing=>$missing_mode}, $maxfiles);

		my $expected = {
			missing => [map { {relfilename => $_} } @missing[0..$n_or_files-1]],
			existing=> [map { {relfilename => $_} } @existing],
			new =>[map { {relfilename => $_} } @new],
		};
		cmp_deeply($J->{listing}{new}, $expected->{new});
		cmp_deeply($J->{listing}{existing}, $expected->{existing});

		is scalar @{$J->{listing}{missing}}, $n_or_files;
		my %m = map { $_ => 1 } @missing;
		for (@{$J->{listing}{missing}}) {
			ok delete $m{$_->{relfilename}}, $_->{relfilename};
		}

		ok($File::Find::prune == 0);
	}
}

# all modes should work
for my $missing_mode (qw/0 1/) { for my $new_mode (qw/0 1/) { for my $existing_mode (qw/0 1/) {
	my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

	my @existing = qw{file2 file3 file4};
	my @missing = qw{fileA fileB fileC};
	my @new = qw{file1 file5 file6 file7};

	$J->{journal_h} = { map { $_ => { relfilename => $_ } } (@existing, @missing) };

	(my $mock_journal = Test::MockModule->new('App::MtAws::Journal'))->
		mock('_is_file_exists', sub {  $_[1] =~ /file\d$/ });

	(my $mock_find = Test::MockModule->new('File::Find'))->
		mock('find', sub {
			my ($args) = @_;
			$args->{wanted}->() for (map "$rootdir/$_", (@new, @existing));
		});

	$File::Find::prune = 0;
	$J->read_files({new=>$new_mode, existing=>$existing_mode, missing=>$missing_mode});

	my $expected = {
		missing => [$missing_mode ? map { {relfilename => $_} } @missing : ()],
		existing=> [$existing_mode ? map { {relfilename => $_} } @existing : ()],
		new =>[$new_mode ? map { {relfilename => $_} } @new : ()],
	};
	cmp_deeply($J->{listing}{new}, $expected->{new});
	cmp_deeply($J->{listing}{existing}, $expected->{existing});
	cmp_deeply([sort map $_->{relfilename}, @{$J->{listing}{missing}}], [sort map $_->{relfilename}, @{$expected->{missing}}]);

	ok($File::Find::prune == 0);
}}}



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

	$J->read_files({new=>1, existing=>1}, 0);
	cmp_deeply($J->{listing}, {new=>[],existing=>[],missing=>[]});
}

# should list file as missing if it does not exist
{
	my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

	my @filelist = qw{root_dir/file1 root_dir/file2 root_dir/file3 root_dir/file4 root_dir/file5 root_dir/file6 root_dir/file7};
	$J->{journal_h} = { map { $_ => { relfilename => $_ } } (@filelist) };
	(my $mock_journal = Test::MockModule->new('App::MtAws::Journal'))->
		mock('_is_file_exists', sub { return 0 });

	(my $mock_find = Test::MockModule->new('File::Find'))->
		mock('find', sub {
			my ($args) = @_;
			$args->{wanted}->() for (@filelist);
		});

	$J->read_files({new=>1, existing=>1, missing=>1}, 0);
	cmp_deeply([sort map $_->{relfilename}, @{$J->{listing}{missing}}], [sort @filelist]);
}

# should not list file as missing if it exists
{
	my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

	my @filelist = qw{root_dir/file1 root_dir/file2 root_dir/file3 root_dir/file4 root_dir/file5 root_dir/file6 root_dir/file7};
	$J->{journal_h} = { map $_ => { relfilename => $_ }, (@filelist) };
	(my $mock_journal = Test::MockModule->new('App::MtAws::Journal'))->
		mock('_is_file_exists', sub { return 1 });

	(my $mock_find = Test::MockModule->new('File::Find'))->
		mock('find', sub {
			my ($args) = @_;
			$args->{wanted}->() for (@filelist);
		});

	$J->read_files({new=>1, existing=>1, missing=>1}, 0);
	ok eq_deeply($J->{listing}{existing}, []);
	ok !eq_deeply($J->{listing}{new}, []);
	cmp_deeply($J->{listing}{missing}, []);
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

	ok ! defined eval { $J->read_files({new=>1, existing=>1}, 0); 1; };
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

	ok ! defined eval { $J->read_files({new=>1, existing=>1}, 0); 1; };
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

	$J->read_files({new=>1, existing=>1}, 0);
	cmp_deeply($J->{listing}, {new=>[],existing=>[], missing => []});
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
			$args->{wanted}->() for (map "$rootdir/$_", @filelist);
		});

	$J->read_files({new=>1, existing=>1}, 0);
	ok($args->{no_chdir} == 1);
	ok($root_dir eq $rootdir);
	ok(defined($args->{wanted}));
	ok(!defined($args->{preprocess}));
}

# preprocess sub should decode to utf8
# should call _can_read_filename_for_mode

1;
