#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 3;
use Test::Deep;
use lib qw{.. ../..};
use Journal;
use Test::MockModule;


my $rootdir = 'root_dir';

#type=> 'CREATED', time => time(), archive_id => $archive_id, filesize => $data->{filesize}, final_hash => $data->{final_hash}, relfilename => $data->{relfilename}
my $data = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	size => 7684356,
	'time' => 1355666755,
	mtime => 1355566755,
	relfilename => 'def/abc',
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
	jobid => '6JpQ39WaMaD8O2N5BU5ieEPyAwtGLNdmNmYvomLjvD4JpivO3GwfCWs_sDnla6gl1Y9v-ceUdqU-pqaaz8FgOqc-yxZG'
};

#
# Test parsing line of Journal version 'A'
#

# CREATED /^A\t(\d+)\tCREATED\t(\S+)\t(\d+)\t(\d+)\t(\S+)\t(.*?)$/
{
		my $J = Journal->new(output_version => 'A', journal_file=>'x', root_dir => $rootdir);

		my ($line);
		
		my $mock = Test::MockModule->new('Journal');
		$mock->mock('_write_line', sub {	(undef, $line) = @_;	});
		$mock->mock('_time', sub {	$data->{time} });
		
		$J->add_entry({ type=> 'CREATED', mtime => $data->{mtime}, archive_id => $data->{archive_id}, size => $data->{size}, treehash => $data->{treehash}, relfilename => $data->{relfilename} });
		ok($line eq "A\t$data->{time}\tCREATED\t$data->{archive_id}\t$data->{size}\t$data->{mtime}\t$data->{treehash}\t$data->{relfilename}");
}

# DELETED
{
		my $J = Journal->new(output_version => 'A', journal_file=>'x', root_dir => $rootdir);

		my ($line);
		
		my $mock = Test::MockModule->new('Journal');
		$mock->mock('_write_line', sub {	(undef, $line) = @_;	});
		$mock->mock('_time', sub {	$data->{time} });
		
		$J->add_entry({ type=> 'DELETED', archive_id => $data->{archive_id}, relfilename => $data->{relfilename} });
		ok($line eq "A\t$data->{time}\tDELETED\t$data->{archive_id}\t$data->{relfilename}");
}

# RETRIEVE_JOB
{
		my $J = Journal->new(output_version => 'A', journal_file=>'x', root_dir => $rootdir);

		my ($line);
		
		my $mock = Test::MockModule->new('Journal');
		$mock->mock('_write_line', sub {	(undef, $line) = @_;	});
		$mock->mock('_time', sub {	$data->{time} });
		
		$J->add_entry({ type=> 'RETRIEVE_JOB', archive_id => $data->{archive_id}, job_id => $data->{jobid}});
		ok($line eq "A\t$data->{time}\tRETRIEVE_JOB\t$data->{archive_id}\t$data->{jobid}");
}

1;

