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
use Test::More tests => 5573;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::Journal;
use App::MtAws::Exceptions;
use App::MtAws::Utils;
use Test::MockModule;
use TestUtils;

warning_fatal();

my $rootdir = 'root_dir';

my $data_sample = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	job_id => "HdGDbije6lWPT8Q8S3uOWJF6777MWRlrfMGDr688888888888zwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	size => 7684356,
	'time' => 1355666755,
	mtime => 1355566755,
	relfilename => 'def/abc',
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
};



#
# kinda unit test
#
test_all_ok($data_sample);

#
# that's looks more like integration tests
#

# mtime formats

for my $mtime (qw/1355566755 -1969112106 +1355566755 -1 0 +0 -0 1 2 3 4 5 6 7 8 9 12 123/) {
	test_all_ok($data_sample, mtime => $mtime);
	test_all_ok($data_sample, mtime => $mtime, relfilename => $data_sample->{archive_id}, _mtime_should_be_undef => 1, _versions => [qw/A/]);
}
test_all_ok($data_sample, mtime => 'NONE', _mtime_should_be_undef => 1, _versions => [qw/B C/]);

for my $mtime (qw/z тест 1111111111111111111111111111111111111111111111111111111111111 1+1 none/, '1,1', '1.1', "\x{7c0}") {
	test_all_fails_for_create_A($data_sample, mtime => $mtime);
}
test_all_fails_for_create_A($data_sample, mtime => 'NONE', _versions => [qw/A/]);

# time formats
for my $time (qw/1355566755 0 1 2 3 4 5 6 7 8 9 12 123/) {
	test_all_ok($data_sample, time => $time);
}

for my $time (qw/z тест 1111111111111111111111111111111111111111111111111111111111111 1+1 -1 NONE none/, '1,1', '1.1', "\x{7c0}") {
	test_all_fails_for_create_A($data_sample, time => $time);
	test_all_fails_for_create_07($data_sample, time => $time);
	test_all_fails_for_delete($data_sample, time => $time);
	test_all_fails_for_retrieve($data_sample, time => $time);
}

# size formats

for my $size (qw/1355566755 1 2 3 4 5 6 7 8 9 12 123/) {
	test_all_ok($data_sample, size => $size);
}

for my $size (qw/z тест 1111111111111111111111111111111111111111111111111111111111111 1+1 -1/, '1,1', '1.1', "\x{7c0}") {
	test_all_fails_for_create_A($data_sample, size => $size);
	test_all_fails_for_create_07($data_sample, size => $size);
}

# delimiters


for my $position (1..5) {
	for my $delimiter ("\t", "\x{202F}", "\x0A", "0x0D") {
		test_all_fails_for_create_07($data_sample, _delimiter => $delimiter, _delimiter_index => $position);
		# TODO: test not only create!
	}
}


for my $position (1..7) {
	for my $delimiter (" ", "  ", "\x{202F}", "\x0A", "0x0D") {
		test_all_fails_for_create_A($data_sample, _delimiter => $delimiter, _delimiter_index => $position);
		# TODO: test not only create!
	}
}

# line formats

{

	my $last_supported_version = 'C';

	# versions A-Z
	my $data =$data_sample;
	for my $v (chr(ord($last_supported_version)+1)..'Z') {
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
		my $line = "$v\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}";
		assert_raises_exception {
			$J->process_line($line, 11);
		}, exception journal_format_error_future => "Invalid format of journal, line %lineno% is from future version of mtglacier", lineno => 11 ;
	}
	for my $v ('A'..$last_supported_version) {
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
		my $line = "$v\tbroken";
		assert_raises_exception {
			$J->process_line($line, 11);
		}, exception journal_format_error_broken => "Invalid format of journal, line %lineno% is broken: %line%",
			lineno => 11, line => hex_dump_string($line);
	}
	# version '0'
	{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
		my $line = "123456 fff";
		assert_raises_exception {
			$J->process_line($line, 11);
		}, exception journal_format_error_broken => "Invalid format of journal, line %lineno% is broken: %line%",
			lineno => 11, line => hex_dump_string($line);
	}
	# version unknown
	{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);
		my $line = "broken\tline";
		assert_raises_exception {
			$J->process_line($line, 11);
		}, exception journal_format_error_unknown => "Invalid format of journal, line %lineno% is in unknown format: %line%",
			lineno => 11, line => hex_dump_string($line);
	}
}

# relfilename formats

for my $relfilename ('0', 'тест', 'тест/тест', 'a/b/c/d/e') {
	test_all_ok($data_sample, relfilename => $relfilename);
}

sub test_all_ok
{
	my ($data_sample, %override) = @_;
	my $data;
	%$data = %$data_sample;
	@$data{keys %override} = values %override;


	#
	# Test parsing line of Journal version 'A', 'B', 'C'
	#

	my @versions = $data->{_versions} ? @{$data->{_versions}} : qw/A B C/;
	for my $ver (@versions) {
		# CREATED /^A\t(\d+)\tCREATED\t(\S+)\t(\d+)\t(\d+)\t(\S+)\t(.*?)$/
		{
			my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

			my ($args);

			(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
				mock('_add_filename', sub { (undef, $args) = @_; });

			$J->process_line("$ver\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}");
			$J->_index_archives_as_files();
			ok($args);

			ok is_iv_without_pv $args->{$_} for (qw/time size/);
			ok ( !defined($args->{mtime}) || is_iv_without_pv($args->{mtime}) );

			ok( $args->{$_} eq $data->{$_}, $_) for qw/archive_id size time treehash/;



			ok ( ( $data->{_mtime_should_be_undef} && !defined($args->{mtime}) )
				or ( !$data->{_mtime_should_be_undef} && $data->{mtime} == $args->{mtime} ));
			ok( $J->absfilename($args->{relfilename}) eq File::Spec->rel2abs($data->{relfilename}, $rootdir));
			is_deeply($J->{used_versions}, {$ver=>1});
		}

		# DELETED /^A\t(\d+)\tDELETED\t(\S+)\t(.*?)$/
		{
			my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

			my ($archive_id);

			(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
				mock('_delete_archive', sub { (undef, $archive_id) = @_; });

			$J->process_line("$ver\t$data->{time}\tDELETED\t$data->{archive_id}\t$data->{relfilename}");
			ok(defined $archive_id);
			ok($archive_id eq $data->{archive_id});
			is_deeply($J->{used_versions}, {$ver=>1});
		}

		#  RETRIEVE_JOB
		{
			my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

			my ($time, $archive_id, $job_id);

			(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
				mock('_retrieve_job', sub { (undef, $time, $archive_id, $job_id) = @_; });

			$J->process_line("$ver\t$data->{time}\tRETRIEVE_JOB\t$data->{archive_id}\t$data->{job_id}");
			ok is_iv_without_pv $time;

			ok(defined($time) && $archive_id && $job_id);
			ok($time == $data->{time});
			ok($archive_id eq $data->{archive_id});
			ok($job_id eq $data->{job_id});
			is_deeply($J->{used_versions}, {$ver=>1});
		}
	}
	#
	# Test parsing line of Journal version '0'
	#


	# CREATED /^(\d+)\s+CREATED\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*?)$/
	{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($args);

		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_add_filename', sub { (undef, $args) = @_; });

		$J->process_line("$data->{time} CREATED $data->{archive_id} $data->{size} $data->{treehash} $data->{relfilename}");
		$J->_index_archives_as_files();

		ok($args);
		ok is_iv_without_pv $args->{$_} for (qw/time size/);

		ok( $args->{$_} eq $data->{$_}, $_) for qw/archive_id size time treehash/;
		ok( $J->absfilename($args->{relfilename}) eq File::Spec->rel2abs($data->{relfilename}, $rootdir));

		is_deeply($J->{used_versions}, {'0'=>1});
	}

	# DELETED /^\d+\s+DELETED\s+(\S+)\s+(.*?)$/
	{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($archive_id);

		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_delete_archive', sub { (undef, $archive_id) = @_; });

		$J->process_line("$data->{time} DELETED $data->{archive_id} $data->{relfilename}");
		ok(defined $archive_id);
		ok($archive_id eq $data->{archive_id});
		is_deeply($J->{used_versions}, {'0'=>1});
	}

	#  RETRIEVE_JOB
	{
	my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

	my ($time, $archive_id, $job_id);

	(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
		mock('_retrieve_job', sub { (undef, $time, $archive_id, $job_id) = @_; });

	$J->process_line("$data->{time} RETRIEVE_JOB $data->{archive_id}");

	ok is_iv_without_pv $time;

	ok(defined($time) && $archive_id);
	ok($time == $data->{time});
	ok($archive_id eq $data->{archive_id});
	ok(! defined $job_id);
	is_deeply($J->{used_versions}, {'0'=>1});
	}

}


sub test_all_fails_for_create_A
{
	my ($data_sample, %override) = @_;
	my $data;
	%$data = %$data_sample;
	@$data{keys %override} = values %override;


	#
	# Test parsing line of Journal version 'A'
	#

	# CREATED /^A\t(\d+)\tCREATED\t(\S+)\t(\d+)\t(\d+)\t(\S+)\t(.*?)$/
	my @versions = $data->{_versions} ? @{$data->{_versions}} : qw/A B C/;
	for my $ver (@versions) {
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my $called = 0;

		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_add_archive', sub { $called = 1 });

		my %D;
		$D{$_} = "\t" for (1..7);

		if (defined $data->{_delimiter}) {
			ok defined $data->{_delimiter_index};
			$D{$data->{_delimiter_index}} = $data->{_delimiter};
		}

		ok ! defined eval { $J->process_line(join('', $ver, $D{1}, $data->{time}, $D{2}, 'CREATED', $D{3}, $data->{archive_id}, $D{4},
			$data->{size}, $D{5}, $data->{mtime}, $D{6}, $data->{treehash}, $D{7}, $data->{relfilename})); 1; };
		ok(! $called);
		is_deeply($J->{used_versions}, {});
	}


}

sub test_all_fails_for_create_07
{
	my ($data_sample, %override) = @_;
	my $data;
	%$data = %$data_sample;
	@$data{keys %override} = values %override;


	#
	# Test parsing line of Journal version '0'
	#


	# CREATED /^(\d+)\s+CREATED\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*?)$/
	{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my $called = 0;

		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_add_archive', sub { $called = 1});

		my %D;
		$D{$_} = ' ' for (1..5);

		if (defined $data->{_delimiter}) {
			ok defined $data->{_delimiter_index};
			$D{$data->{_delimiter_index}} = $data->{_delimiter};
		}

		ok ! defined eval { $J->process_line(join('', $data->{time}, $D{1}, 'CREATED', $D{2}, $data->{archive_id}, $D{3}, $data->{size},
			$D{4}, $data->{treehash}, $D{5}, $data->{relfilename})); 1; };
		ok(! $called);
		is_deeply($J->{used_versions}, {});
	}

}

sub test_all_fails_for_delete
{
	my ($data_sample, %override) = @_;
	my $data;
	%$data = %$data_sample;
	@$data{keys %override} = values %override;


	# DELETED /^A\t(\d+)\tDELETED\t(\S+)\t(.*?)$/
	my @versions = $data->{_versions} ? @{$data->{_versions}} : qw/A B C/;
	for my $ver (@versions) {
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my $called = 0;

		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_delete_archive', sub { $called = 1});

		ok ! defined eval { $J->process_line("$ver\t$data->{time}\tDELETED\t$data->{archive_id}\t$data->{relfilename}"); 1; };
		ok (! $called);
		is_deeply($J->{used_versions}, {});
	}

	#
	# Test parsing line of Journal version '0'
	#


	# DELETED /^\d+\s+DELETED\s+(\S+)\s+(.*?)$/
	{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my $called = 0;

		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_delete_archive', sub { $called = 1 });

		ok ! defined eval { $J->process_line("$data->{time} DELETED $data->{archive_id} $data->{relfilename}"); 1; };
		ok(! $called);
		is_deeply($J->{used_versions}, {});
	}
}

sub test_all_fails_for_retrieve
{
	my ($data_sample, %override) = @_;
	my $data;
	%$data = %$data_sample;
	@$data{keys %override} = values %override;


	# DELETED /^A\t(\d+)\tDELETED\t(\S+)\t(.*?)$/
	my @versions = $data->{_versions} ? @{$data->{_versions}} : qw/A B C/;
	for my $ver (@versions) {
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my $called = 0;

		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_retrieve_job', sub { $called =1 });

		ok ! defined eval { $J->process_line("$ver\t$data->{time}\tRETRIEVE_JOB\t$data->{archive_id}\t$data->{job_id}"); 1 };

		ok (!$called);
		is_deeply($J->{used_versions}, {});
	}

	#
	# Test parsing line of Journal version '0'
	#


	# DELETED /^\d+\s+DELETED\s+(\S+)\s+(.*?)$/
	{
		my $J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir);

		my $called = 0;

		(my $mock = Test::MockModule->new('App::MtAws::Journal'))->
			mock('_retrieve_job', sub { $called =1 });

		ok ! defined eval { $J->process_line("$data->{time} RETRIEVE_JOB $data->{archive_id}"); 1; };

		ok (!$called);
		is_deeply($J->{used_versions}, {});
	}
}

1;
