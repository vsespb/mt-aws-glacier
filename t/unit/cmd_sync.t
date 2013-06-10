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
use Test::Spec;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Journal;
use File::Path;
use POSIX;
use TestUtils;
use POSIX;
use Time::Local;
use Carp;
use App::MtAws::MetaData;
use App::MtAws::DownloadInventoryCommand;
use File::Temp ();
use Data::Dumper;
require App::MtAws::SyncCommand;

warning_fatal();



describe "command" => sub {
	it "should work" => sub {
		my $options = { 'max-number-of-files' => 10, partsize => 2 };
		my $j = App::MtAws::Journal->new(journal_file => 'x', 'root_dir' => 'x' );
		App::MtAws::SyncCommand->expects("with_forks")->returns(sub{
			my ($flag, $options, $cb) = @_;
			is $flag, !$options->{'dry-run'};
			is $options, $options;
			$cb->();
		});
		App::MtAws::Journal->expects("read_journal")->returns(sub {
			shift;
			cmp_deeply [@_], [should_exist => 0];
		})->once;
		App::MtAws::Journal->expects("read_new_files")->returns(sub { is $_[1], $options->{'max-number-of-files'}} )->once;
		App::MtAws::Journal->expects("open_for_write")->once;
		App::MtAws::Journal->expects("close_for_write")->once;
		
		App::MtAws::SyncCommand->expects("fork_engine")->returns(sub {
			bless { parent_worker =>
				bless {}, 'App::MtAws::ParentWorker'
			}, 'App::MtAws::ForkEngine';
		})->once;
		
		my @files = qw/file1 file2 file3 file4/;
		
		App::MtAws::ParentWorker->expects("process_task")->returns(sub {
			ok $_[1]->isa('App::MtAws::JobListProxy');
			my @jobs = @{$_[1]->{jobs}};
			for (@files) {
				my $job = shift @jobs;
				is $job->{job}{relfilename}, $_;
				is $job->{job}{partsize}, $options->{partsize}*1024*1024;
				ok $job->isa('App::MtAws::JobProxy');
				ok $job->{job}->isa('App::MtAws::FileCreateJob');
			}
			return (1)
		} )->once;
		
		$j->{newfiles_a} = [ map { { relfilename => $_ }} @files ];
		
		App::MtAws::SyncCommand::run($options, $j);
	};
};

runtests unless caller;

1;
