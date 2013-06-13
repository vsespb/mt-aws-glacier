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
use Test::More tests => 38;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use App::MtAws::Filter;
use TestUtils;

warning_fatal();

# should work
{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_file(file1 => { relfilename => 'file1' });
	cmp_deeply $j->{journal_h}, {file1 => { relfilename => 'file1' }}, "adding new file should work";
} 


# working with FileVersions
{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	$j->_add_file($obj1->{relfilename} => $obj1);
	$j->_add_file($obj2->{relfilename} => $obj2);
	is scalar keys %{$j->{journal_h}}, 1, "should add second file - one key";
	ok $j->{journal_h}->{file1}, "should add second file - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add second file - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1], "should add second file - versions dhoule be in right order";
} 

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	$j->_add_file(file2 => { relfilename => 'file2', archive_id => 'b2', time => 42, mtime => undef });
	$j->_add_file($obj1->{relfilename} => $obj1);
	$j->_add_file($obj2->{relfilename} => $obj2);
	is scalar keys %{$j->{journal_h}}, 2, "should add second file if there are multiple files";
	ok $j->{journal_h}->{file1}, "should add second file - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add second file - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1], "should add second file - versions dhoule be in right order";
} 

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	my $obj3 = { relfilename => 'file1', archive_id => 'a3', time => 456, mtime => undef };
	$j->_add_file($obj1->{relfilename} => $obj1);
	$j->_add_file($obj2->{relfilename} => $obj2);
	$j->_add_file($obj2->{relfilename} => $obj3);
	is scalar keys %{$j->{journal_h}}, 1, "should add third file - one key";
	ok $j->{journal_h}->{file1}, "should add third file - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add third file - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1, $obj3], "should add third file - versions dhoule be in right order";
} 

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	my $obj3 = { relfilename => 'file1', archive_id => 'a3', time => 456, mtime => undef };
	$j->_add_file(file2 => { relfilename => 'file2', archive_id => 'b2', time => 42, mtime => undef });
	$j->_add_file($obj1->{relfilename} => $obj1);
	$j->_add_file($obj2->{relfilename} => $obj2);
	$j->_add_file($obj2->{relfilename} => $obj3);
	is scalar keys %{$j->{journal_h}}, 2, "should add third file is there are multiple files";
	ok $j->{journal_h}->{file1}, "should add third file - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add third file - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1, $obj3], "should add third file - versions dhoule be in right order";
} 

# working with filter
{
	my $filter= App::MtAws::Filter->new();
	my $j = App::MtAws::Journal->new('journal_file' => '.', filter => $filter);
	my $called = 0;
	no warnings 'redefine';
	local *App::MtAws::Filter::check_filenames = sub {
		my ($self, $relfilename) = @_;
		++$called;
		is $self, $filter, "should filter usign right object";
		is $relfilename, 'file1', "should call filter with correct filename";
		1;
	};
	$j->_add_file(file1 => { relfilename => 'file1' });
	cmp_deeply $j->{journal_h}, {file1 => { relfilename => 'file1' }}, "adding file with filter should work";
	is $called, 1, "should be called just once";
} 

{
	my $filter= App::MtAws::Filter->new();
	my $j = App::MtAws::Journal->new('journal_file' => '.', filter => $filter);
	my $called = 0;
	no warnings 'redefine';
	local *App::MtAws::Filter::check_filenames = sub {
		my ($self, $relfilename) = @_;
		++$called;
		is $self, $filter, "should filter usign right object";
		is $relfilename, 'file1', "should call filter with correct filename";
		1;
	};
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	$j->_add_file($obj1->{relfilename} => $obj1);
	$j->_add_file($obj2->{relfilename} => $obj2);
	is scalar keys %{$j->{journal_h}}, 1, "should add second file with filter if there are multiple files";
	ok $j->{journal_h}->{file1}, "should add second file with filter - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add second file with filter - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1], "should add second file with filter - versions dhoule be in right order";
	is $called, 1, "filter should be called just once, even if there are two versions";
} 

{
	my $filter= App::MtAws::Filter->new();
	my $j = App::MtAws::Journal->new('journal_file' => '.', filter => $filter);
	my $called = 0;
	no warnings 'redefine';
	local *App::MtAws::Filter::check_filenames = sub {
		my ($self, $relfilename) = @_;
		++$called;
		is $self, $filter, "should filter usign right object";
		is $relfilename, 'file1', "should call filter with correct filename";
		0;
	};
	$j->_add_file(file1 => { relfilename => 'file1' });
	cmp_deeply $j->{journal_h}, {}, "should not add file if filter returned false";
	is $called, 1, "should be called just once";
} 

{
	my $filter= App::MtAws::Filter->new();
	my $j = App::MtAws::Journal->new('journal_file' => '.', filter => $filter);
	my $called = 0;
	no warnings 'redefine';
	local *App::MtAws::Filter::check_filenames = sub {
		my ($self, $relfilename) = @_;
		++$called;
		is $self, $filter, "should filter usign right object";
		is $relfilename, 'file1', "should call filter with correct filename";
		0;
	};
	$j->_add_file(file1 => { relfilename => 'file1', time => 1 });
	$j->_add_file(file1 => { relfilename => 'file1', time => 2 });
	cmp_deeply $j->{journal_h}, {}, "should not add file if filter returned false, even multiple versions";
	is $called, 2, "filter should be called twice";
} 

1;

