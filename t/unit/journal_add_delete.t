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
use Test::More tests => 45;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use App::MtAws::Filter;
use TestUtils;

warning_fatal();

# _add_filename
{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_filename({ relfilename => 'file1' });
	cmp_deeply $j->{journal_h}, {file1 => { relfilename => 'file1' }}, "adding new file should work";
} 


# _add_filename - working with FileVersions
{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	$j->_add_filename($obj1);
	$j->_add_filename($obj2);
	is scalar keys %{$j->{journal_h}}, 1, "should add second file - one key";
	ok $j->{journal_h}->{file1}, "should add second file - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add second file - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1], "should add second file - versions should be in right order";
} 

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	$j->_add_filename({ relfilename => 'file2', archive_id => 'b2', time => 42, mtime => undef });
	$j->_add_filename($obj1);
	$j->_add_filename($obj2);
	is scalar keys %{$j->{journal_h}}, 2, "should add second file if there are multiple files";
	ok $j->{journal_h}->{file1}, "should add second file - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add second file - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1], "should add second file - versions should be in right order";
} 

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	my $obj3 = { relfilename => 'file1', archive_id => 'a3', time => 456, mtime => undef };
	$j->_add_filename($obj1);
	$j->_add_filename($obj2);
	$j->_add_filename($obj3);
	is scalar keys %{$j->{journal_h}}, 1, "should add third file - one key";
	ok $j->{journal_h}->{file1}, "should add third file - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add third file - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1, $obj3], "should add third file - versions should be in right order";
} 

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file1', archive_id => 'a2', time => 42, mtime => undef };
	my $obj3 = { relfilename => 'file1', archive_id => 'a3', time => 456, mtime => undef };
	$j->_add_filename({ relfilename => 'file2', archive_id => 'b2', time => 42, mtime => undef });
	$j->_add_filename($obj1);
	$j->_add_filename($obj2);
	$j->_add_filename($obj3);
	is scalar keys %{$j->{journal_h}}, 2, "should add third file is there are multiple files";
	ok $j->{journal_h}->{file1}, "should add third file - key is correct";
	is ref $j->{journal_h}->{file1}, 'App::MtAws::FileVersions', 'should add third file - reference should be blessed into FileVersions';
	cmp_deeply [$j->{journal_h}->{file1}->all()], [$obj2, $obj1, $obj3], "should add third file - versions should be in right order";
} 

# latest()

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj1 = { relfilename => 'file1', archive_id => 'a1', time => 123, mtime => undef };
	my $obj2 = { relfilename => 'file2', archive_id => 'a2', time => 42, mtime => undef };
	my $obj3 = { relfilename => 'file2', archive_id => 'a3', time => 43, mtime => undef };
	my $obj4 = { relfilename => 'file4', archive_id => 'a4', time => 123, mtime => undef };
	$j->_add_filename($obj1);
	is $j->latest('file1')->{archive_id}, 'a1', "latest should work";
	$j->_add_filename($obj2);
	is $j->latest('file2')->{archive_id}, 'a2', "latest should FileVersions";
	$j->_add_filename($obj3);
	is $j->latest('file2')->{archive_id}, 'a3', "latest should work with FileVersions when there are two elements";
	$j->_add_filename($obj4);
	is $j->latest('file4')->{archive_id}, 'a4', "latest should with multiple files";
} 

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj2 = { relfilename => 'file2', archive_id => 'a2', time => 42, mtime => undef };
	my $obj3 = { relfilename => 'file2', archive_id => 'a3', time => 43, mtime => undef };
	$j->_add_filename($obj2);
	$j->_add_filename($obj3);
	no warnings 'redefine';
	my $saved = undef;
	local *App::MtAws::FileVersions::latest = sub { $saved = shift; "TEST" };
	is $j->latest('file2'), 'TEST', "latest call FileVersions latest()";
	ok $saved->isa('App::MtAws::FileVersions'), 'latest call FileVersions latest() right';
} 

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	my $obj2 = { relfilename => 'file2', archive_id => 'a2', time => 42, mtime => undef };
	$j->_add_filename($obj2);
	ok ! defined eval { $j->latest('not-a-file'); 1 }, "should confess if file not found";
} 

# _add_archive

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123' });
	cmp_deeply $j->{archive_h}, {'abc123' => { relfilename => 'file1', archive_id => 'abc123' }}, "_add_archive should work";
}

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123' });
	$j->_add_archive({ relfilename => 'file1', archive_id => 'def123' });
	cmp_deeply $j->{archive_h}, {
		'abc123' => { relfilename => 'file1', archive_id => 'abc123' },
		'def123' => { relfilename => 'file1', archive_id => 'def123' }
	}, "_add_archive should work with two archives";
}

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123' });
	ok ! defined eval { $j->_add_archive({ relfilename => 'file2', archive_id => 'abc123' }); 1 }, "_add_archive should confess";
}

# _delete_archive


{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123' });
	$j->_delete_archive('abc123');
	cmp_deeply $j->{archive_h}, {}, "_delete_archive should work";
}

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123' });
	$j->_add_archive({ relfilename => 'file1', archive_id => 'fff123' });
	$j->_delete_archive('abc123');
	cmp_deeply $j->{archive_h}, { fff123 => { relfilename => 'file1', archive_id => 'fff123' }}, "_delete_archive should work with two archives";
}

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123' });
	ok ! defined eval { $j->_delete_archive('zzzz');; 1 }, "_delete_archive should confess";
}


# _add_archive - working with filter
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
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123' });
	cmp_deeply $j->{archive_h}, {'abc123' => { relfilename => 'file1', archive_id => 'abc123' }}, "adding file with filter should work";
	is $called, 1, "should be called once";
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
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123' });
	cmp_deeply $j->{archive_h}, {}, "should not add file if filter returned false";
	is $called, 1, "should be called just once";
} 


# _index_archives_as_files

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123', time => 123 });
	$j->_add_archive({ relfilename => 'file1', archive_id => 'def123', time => 42 });
	$j->_add_archive({ relfilename => 'file2', archive_id => 'xyz123', time => 456 });
	cmp_deeply $j->{archive_h}, {
		'abc123' => { relfilename => 'file1', archive_id => 'abc123', time => 123  },
		'def123' => { relfilename => 'file1', archive_id => 'def123', time => 42  },
		'xyz123' => { relfilename => 'file2', archive_id => 'xyz123', time => 456  }
	}, "should have correct archive_h";
	no warnings 'redefine';
	my @saved;
	local *App::MtAws::Journal::_add_filename = sub {
		my ($self, $args) = @_;
		push @saved, $args;
	};
	$j->_index_archives_as_files();
	cmp_deeply [ sort map { $_->{archive_id} }@saved ], [sort qw/abc123 def123 xyz123/], "_index_archives_as_files should do right thing";
}

{
	my $j = App::MtAws::Journal->new('journal_file' => '.');
	$j->_add_archive({ relfilename => 'file1', archive_id => 'abc123', time => 123 });
	$j->_add_archive({ relfilename => 'file1', archive_id => 'def123', time => 42 });
	$j->_add_archive({ relfilename => 'file2', archive_id => 'xyz123', time => 456 });
	cmp_deeply $j->{archive_h}, {
		'abc123' => { relfilename => 'file1', archive_id => 'abc123', time => 123  },
		'def123' => { relfilename => 'file1', archive_id => 'def123', time => 42  },
		'xyz123' => { relfilename => 'file2', archive_id => 'xyz123', time => 456  }
	}, "should have correct archive_h";
	$j->_index_archives_as_files();
	is keys %{$j->{journal_h}}, 2, "should have two filenames";
	cmp_deeply $j->{journal_h}{file2}, { relfilename => 'file2', archive_id => 'xyz123', time => 456  }, "should store file2 as hash";
	is ref $j->{journal_h}{file1}, 'App::MtAws::FileVersions', "should store file1 versioned";
	cmp_deeply [map { $_->{archive_id} } $j->{journal_h}->{file1}->all()], [qw/def123 abc123/], "should store file1 versioned";
}



1;

