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
use Test::More tests => 18;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use File::Path;
use POSIX;
use File::Temp;
use TestUtils;

warning_fatal();


my $TEMP = File::Temp->newdir();
my $mtroot = $TEMP->dirname();
my $localroot = "$mtroot/cmd_retrieve";
my $journal = "$localroot/journal";
my $rootdir = "$localroot/root";
rmtree($localroot);
mkpath($localroot);
mkpath($rootdir);
mkpath($rootdir."/def");


my $relfilename = 'def/abc';
my $data = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	job_id => "HdGDbije6lWPT82222222226Ou9MWRlrfMGDr6T3rhXuDq33333333334l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	size => 7684356,
	'time' => 1355666755,
	mtime => 1355566755,
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
};



require App::MtAws::RetrieveCommand;


{
	my $J;

	my $options = {
		'max-number-of-files' => 3,
	};
	
	{
		$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
		$J->{last_read_time} = $data->{'time'} + 10;
	
		my $d =  {
			time => $data->{'time'} - 20,
			archive_id => $data->{archive_id},
			size => $data->{size},
			mtime => $data->{mtime},
			treehash => $data->{treehash},
		};
			
		$J->_add_file($relfilename, $d);	
		#$J->_retrieve_job($data->{'time'} - 10, $data->{archive_id}, $data->{job_id});
		
		cmp_deeply [App::MtAws::RetrieveCommand::get_file_list($options, $J)],
			[{archive_id => $data->{archive_id}, relfilename => $relfilename, filename => "${rootdir}/$relfilename"}], 'should work';
	}

	{
		$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
		$J->{last_read_time} = $data->{'time'} + 10;
	
		my $d =  {
			time => $data->{'time'} - 20,
			archive_id => $data->{archive_id},
			size => $data->{size},
			mtime => $data->{mtime},
			treehash => $data->{treehash},
		};
			
		$J->_add_file($relfilename, $d);	
		
		open F, ">", "${rootdir}/$relfilename";
		close F;
		is scalar App::MtAws::RetrieveCommand::get_file_list($options, $J), 0, "should skip existing files";
	}
	
	{
		unlink "${rootdir}/$relfilename";
		$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
		$J->{last_read_time} = $data->{'time'} + 10;
	
		my $d =  {
			time => $data->{'time'} - 20,
			archive_id => $data->{archive_id},
			size => $data->{size},
			mtime => $data->{mtime},
			treehash => $data->{treehash},
		};
			
		$J->_add_file($relfilename, $d);	
		$J->_retrieve_job($data->{'time'} - 10, $data->{archive_id}, $data->{job_id});
		
		is scalar App::MtAws::RetrieveCommand::get_file_list($options, $J), 0, "should skip already retrieved files";
	}
}

{
	my $J;

	for my $max (qw/1 2 3 4 5 6 7/) {
		my $options = {
			'max-number-of-files' => $max,
		};
		
		$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
		$J->{last_read_time} = $data->{'time'} + 10;
	
		
		for (1..10) {
			my $d =  {
				time => $data->{'time'} - 20,
				archive_id => $data->{archive_id}."$_",
				size => $data->{size},
				mtime => $data->{mtime},
				treehash => $data->{treehash},
			};
				
			$J->_add_file($relfilename."$_", $d);
		}	
		
		is scalar App::MtAws::RetrieveCommand::get_file_list($options, $J), $max, "should respect max-number-of-files for $max";
	}
}


{
	my $J;

	my $options = {
		'max-number-of-files' => 7,
	};
	
	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;

	
	for (1..9) {
		my $d =  {
			time => $data->{'time'} - 20,
			archive_id => $data->{archive_id}."$_",
			size => $data->{size},
			mtime => $data->{mtime},
			treehash => $data->{treehash},
		};
			
		$J->_add_file($relfilename."$_", $d);
		if ($_ % 2 != 0) {
			open F, ">", "${rootdir}/$relfilename$_";
			close F;
		}
	}	
	
	for (App::MtAws::RetrieveCommand::get_file_list($options, $J)) {
		my ($n) = $_->{relfilename} =~ /(\d)$/;
		ok $n && ($n % 2 == 0), "should skip exsiting retrieved files";
	}
}

{
	my $J;

	my $options = {
		'max-number-of-files' => 7,
	};
	
	$J = App::MtAws::Journal->new(journal_file=>'x', root_dir => $rootdir, use_active_retrievals => 1);
	$J->{last_read_time} = $data->{'time'} + 10;

	
	for (1..9) {
		my $d =  {
			time => $data->{'time'} - 20,
			archive_id => $data->{archive_id}."$_",
			size => $data->{size},
			mtime => $data->{mtime},
			treehash => $data->{treehash},
		};
			
		$J->_add_file($relfilename."$_", $d);
		$J->_retrieve_job($data->{'time'} - 10, $data->{archive_id}."$_", $data->{job_id}."$_") if $_ % 2 != 0;
	}	
	
	for (App::MtAws::RetrieveCommand::get_file_list($options, $J)) {
		my ($n) = $_->{archive_id} =~ /(\d)$/;
		ok $n && ($n % 2 == 0), "should skip already retrieved files";
	}
}
1;

