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
use Test::Spec 0.46;
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

our $order_n;


describe "command" => sub {
	it "new should work" => sub {
		my $options = { 'max-number-of-files' => 10, partsize => 2, new => 1 };
		my $j = App::MtAws::Journal->new(journal_file => 'x', 'root_dir' => 'x' );

		ordered_test sub {
			App::MtAws::SyncCommand->expects("with_forks")->returns_ordered(sub{
				my ($flag, $options, $cb) = @_;
				is $flag, !$options->{'dry-run'};
				is $options, $options;
				$cb->();
			});
			App::MtAws::Journal->expects("read_journal")->with(should_exist => 0)->returns_ordered->once;#returns(sub{ is ++shift->{_stage}, 1 })
			App::MtAws::Journal->expects("read_files")->returns_ordered(sub {
				shift;
				cmp_deeply [@_], [{new=>1}, $options->{'max-number-of-files'}];
			})->once;
			App::MtAws::Journal->expects("open_for_write")->returns_ordered->once;
			
			App::MtAws::SyncCommand->expects("fork_engine")->returns_ordered(sub {
				bless { parent_worker =>
					bless {}, 'App::MtAws::ParentWorker'
				}, 'App::MtAws::ForkEngine';
			})->once;
			
			my @files = qw/file1 file2 file3 file4/;
			
			App::MtAws::ParentWorker->expects("process_task")->returns_ordered(sub {
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
			App::MtAws::Journal->expects("close_for_write")->returns_ordered->once;
			
			$j->{listing}{existing} = [];
			$j->{listing}{new} = [ map { { relfilename => $_ }} @files ];
			
			App::MtAws::SyncCommand::run($options, $j);
		};
	};
};

runtests unless caller;

1;
