#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 22;
use Test::Deep;
use lib qw{.. ../..};
use Journal;
use Test::MockModule;

my $relfilename = 'def/abc';
my $rootdir = 'root_dir';
my $data = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	size => 7684356,
	'time' => 1355666755,
	mtime => 1355566755,
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
#	absfilename => File::Spec->rel2abs($relfilename, $rootdir)
};

#
# Test parsing line of Journal version 'A'
#

# CREATED /^A\t(\d+)\tCREATED\t(\S+)\t(\d+)\t(\d+)\t(\S+)\t(.*?)$/
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($args, $filename);
		
		(my $mock = Test::MockModule->new('Journal'))->
			mock('_add_file', sub {	(undef, $filename, $args) = @_;	});
		
		$J->process_line("A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$relfilename");
		ok($args);
		ok( $args->{$_} eq $data->{$_}, $_) for qw/archive_id size time mtime treehash/;
		ok( $J->absfilename($filename) eq File::Spec->rel2abs($relfilename, $rootdir));
		cmp_deeply($args, superhashof($data));
		is_deeply($J->{used_versions}, {'A'=>1});
}

# DELETED /^A\t(\d+)\tDELETED\t(\S+)\t(.*?)$/
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($filename);
		
		(my $mock = Test::MockModule->new('Journal'))->
			mock('_delete_file', sub {	(undef, $filename) = @_;	});
		
		$J->process_line("A\t$data->{time}\tDELETED\t$data->{archive_id}\t$relfilename");
		ok($filename);
		ok($filename eq $relfilename);
		is_deeply($J->{used_versions}, {'A'=>1});
}

#
# Test parsing line of Journal version '0'
#

# CREATED /^(\d+)\s+CREATED\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*?)$/
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($args, $filename);
		
		(my $mock = Test::MockModule->new('Journal'))->
			mock('_add_file', sub {	(undef, $filename, $args) = @_;	});
		
		$J->process_line("$data->{time} CREATED $data->{archive_id} $data->{size} $data->{treehash} $relfilename");
		ok($args);
		ok( $args->{$_} eq $data->{$_}, $_) for qw/archive_id size time treehash/;
		ok( $J->absfilename($filename) eq File::Spec->rel2abs($relfilename, $rootdir));
		
		is_deeply($J->{used_versions}, {'0'=>1});
}

# DELETED /^\d+\s+DELETED\s+(\S+)\s+(.*?)$/
{
		my $J = Journal->new(journal_file=>'x', root_dir => $rootdir);

		my ($filename);
		
		(my $mock = Test::MockModule->new('Journal'))->
			mock('_delete_file', sub {	(undef, $filename) = @_;	});
		
		$J->process_line("$data->{time} DELETED $data->{archive_id} $relfilename");
		ok($filename);
		ok($filename eq $relfilename);
		is_deeply($J->{used_versions}, {'0'=>1});
}

1;

