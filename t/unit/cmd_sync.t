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
use Test::More tests => 114;
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
	my $j;
	
	before each => sub {
		$j = App::MtAws::Journal->new(journal_file => 'x', 'root_dir' => 'x' );
	};
		
	describe "modified processing" => sub {
		
		my @all_detect = qw/mtime mtime-and-treehash mtime-or-treehash/; # TODO: fetch from ConfigDefinition
		my @detect_with_mtime = grep { /mtime/ } @all_detect;
		my @detect_without_mtime = grep { ! /mtime/ } @all_detect;
		
		describe "is_mtime_differs" => sub {
			it "should work when mtime same" => sub {
				App::MtAws::SyncCommand->expects("file_mtime")->returns(sub{ is shift, 'file1'; 123;})->once;
				ok !App::MtAws::SyncCommand::is_mtime_differs({detect => 'mtime-and-treehash'},{mtime => 123}, 'file1');
			};
			it "should work when mtime greater than" => sub {
				App::MtAws::SyncCommand->expects("file_mtime")->returns(sub{ is shift, 'file1'; 456;})->once;
				ok App::MtAws::SyncCommand::is_mtime_differs({detect => 'mtime-and-treehash'},{mtime => 123}, 'file1');
			};
			it "should work when mtime less than" => sub {
				App::MtAws::SyncCommand->expects("file_mtime")->returns(sub{ is shift, 'file1'; 42;})->once;
				ok App::MtAws::SyncCommand::is_mtime_differs({detect => 'mtime-and-treehash'},{mtime => 123}, 'file1');
			};
			it "should work when detect contans mtime" => sub {
				for (@detect_with_mtime) {
					App::MtAws::SyncCommand->expects("file_mtime")->returns(sub{ is shift, 'file1'; 42;})->once;
					ok App::MtAws::SyncCommand::is_mtime_differs({detect => $_},{mtime => 123}, 'file1');
				}
			};
			it "should work when detect does not contan mtime" => sub {
				for (@detect_without_mtime) {
					App::MtAws::SyncCommand->expects("file_mtime")->never;
					ok ! defined App::MtAws::SyncCommand::is_mtime_differs({detect => $_},{mtime => 123}, 'file1');
				}
			};
		};
		
		describe "should_upload" => sub {
			it "should always return create if file size differs" => sub {
				for (@all_detect) {
					App::MtAws::SyncCommand->expects("is_mtime_differs")->never;
					App::MtAws::SyncCommand->expects("file_size")->returns(42)->once;
					is  App::MtAws::SyncCommand::should_upload({detect => $_},{mtime => 123, size => 43}, 'file1'), 'create';
				}
			};

			sub test_should_upload
			{
				my ($detect, $mtime_differs, $mtime_expected, $expected) = @_;
				my $opts = {detect => $detect};
				my $file = {mtime => 123, size => 42};
				if ($mtime_expected) {
					App::MtAws::SyncCommand->expects("is_mtime_differs")->returns(sub {
						cmp_deeply [$opts, $file, 'file1'], [@_];
						return $mtime_differs;
					})->once
				}
				App::MtAws::SyncCommand->expects("file_size")->returns(42)->once;
				cmp_deeply App::MtAws::SyncCommand::should_upload($opts, $file, 'file1'), $expected;
			}

			describe "detect=mtime" => sub {
				it "should return 'create' when mtime differs" => sub {
					test_should_upload('mtime', 1, 1, 'create');
				};
				it "should return FALSE when mtime same" => sub {
					test_should_upload('mtime', 0, 1, bool(0));
				};
			};

			describe "detect=treehash" => sub {
				it "should return 'treehash' mtime is irrelevant" => sub {
					test_should_upload('treehash', $_, 0, 'treehash') for (0,1);
				};
			};

			describe "detect=mtime-and-treehash" => sub {
				it "should return 'treehash' when mtime differs" => sub {
					test_should_upload('mtime-and-treehash', 1, 1, 'treehash');
				};
				it "should return FALSE when mtime same" => sub {
					test_should_upload('mtime-and-treehash', 0, 1, bool(0));
				};
			};
			
			describe "detect=mtime-or-treehash" => sub {
				it "should return 'create' when mtime differs" => sub {
					test_should_upload('mtime-or-treehash', 1, 1, 'create');
				};
				it "should return 'treehash' when mtime same" => sub {
					test_should_upload('mtime-or-treehash', 0, 1, 'treehash');
				};
			};
		};
		
	};
		
	describe "next_new" => sub {
		my $options;
		before each => sub {
			$options = { partsize => 2};
		};
		it "should work with one file" => sub {
			$j->{listing}{new} = [{relfilename => 'file1'}];
			my $rec = App::MtAws::SyncCommand::next_new($options, $j);
			ok $rec->isa('App::MtAws::JobProxy');
			my $job = $rec->{job};
			is $job->{partsize}, $options->{partsize}*1024*1024;
			is $job->{relfilename}, 'file1';
			is $job->{filename}, $j->absfilename('file1');
			ok $job->isa('App::MtAws::FileCreateJob');
			is scalar @{ $j->{listing}{new} }, 0;
			ok !defined (App::MtAws::SyncCommand::next_new($options, $j)); 
		};
		it "should work with two files" => sub {
			$j->{listing}{new} = [{relfilename => 'file1'}, {relfilename => 'file2'}];
			my $rec = App::MtAws::SyncCommand::next_new($options, $j);
			my $job = $rec->{job};
			is $job->{relfilename}, 'file1';
			is scalar @{ $j->{listing}{new} }, 1;
			$rec = App::MtAws::SyncCommand::next_new($options, $j); 
			$job = $rec->{job};
			is $job->{relfilename}, 'file2';
		};
		it "should work with zero files" => sub {
			$j->{listing}{new} = [];
			ok ! defined( App::MtAws::SyncCommand::next_new($options, $j) );
		};
	};

	describe "next_missing" => sub {
		my $options;
		before each => sub {
			$options = { };
		};
		it "should work with one file" => sub {
			my $r = {relfilename => 'file1', size => 123};
			$j->{listing}{missing} = [$r];
			$j->_add_filename($r);
			my $rec = App::MtAws::SyncCommand::next_missing($options, $j);
			ok $rec->isa('App::MtAws::FileListDeleteJob');
			is scalar @{ $rec->{archives} }, 1;
			my $job = $rec->{archives}[0];
			is $job->{relfilename}, 'file1';
			is scalar @{ $j->{listing}{missing} }, 0;
			ok !defined (App::MtAws::SyncCommand::next_missing($options, $j)); 
		};
		it "should work with two files" => sub {
			for ({relfilename => 'file1', size => 123}, {relfilename => 'file2', size => 456}) {
				push @{ $j->{listing}{missing} }, $_;
				$j->_add_filename($_);
			}
			my $rec = App::MtAws::SyncCommand::next_missing($options, $j);
			ok $rec->isa('App::MtAws::FileListDeleteJob');
			is scalar @{ $rec->{archives} }, 1;
			my $job = $rec->{archives}[0];
			is $job->{relfilename}, 'file1';
			is scalar @{ $j->{listing}{missing} }, 1;
			$rec = App::MtAws::SyncCommand::next_missing($options, $j);
			$job = $rec->{archives}[0];
			is $job->{relfilename}, 'file2';
		};
		it "should work with zero files" => sub {
			$j->{listing}{missing} = [];
			ok ! defined( App::MtAws::SyncCommand::next_missing($options, $j) );
		};
		it "should work with latest version of file" => sub {
			my $r = {relfilename => 'file1', size => 123};
			$j->{listing}{missing} = [$r];
			$j->_add_filename({relfilename => 'file1', archive_id => 'zz1', size => 123, time => 42, mtime => 111});
			$j->_add_filename({relfilename => 'file1', archive_id => 'zz2', size => 123, time => 42, mtime => 113});
			$j->_add_filename({relfilename => 'file1', archive_id => 'zz3', size => 123, time => 42, mtime => 112});
			my $rec = App::MtAws::SyncCommand::next_missing($options, $j);
			ok $rec->isa('App::MtAws::FileListDeleteJob');
			is scalar @{ $rec->{archives} }, 1;
			my $job = $rec->{archives}[0];
			is $job->{archive_id}, 'zz2';
		};
		it "should call latest() to get latest version of file" => sub {
			my $r = {relfilename => 'file1', size => 123};
			$j->{listing}{missing} = [$r];
			$j->_add_filename({relfilename => 'file1', archive_id => 'zz1', size => 123, time => 42, mtime => 111});
			$j->_add_filename(my $r2 = {relfilename => 'file1', archive_id => 'zz2', size => 123, time => 42, mtime => 113});
			App::MtAws::Journal->expects("latest")->with('file1')->returns($r2)->once;
			my $rec = App::MtAws::SyncCommand::next_missing($options, $j);
		};
	};

	describe "run" => sub {
		sub expect_with_forks
		{
			App::MtAws::SyncCommand->expects("with_forks")->returns_ordered(sub{
				my ($flag, $options, $cb) = @_;
				is $flag, !$options->{'dry-run'};
				is $options, $options;
				$cb->();
			});
		}
		
		sub expect_journal_init
		{
			my ($options, $read_files_mode) = @_;
			App::MtAws::Journal->expects("read_journal")->with(should_exist => 0)->returns_ordered->once;#returns(sub{ is ++shift->{_stage}, 1 })
			App::MtAws::Journal->expects("read_files")->returns_ordered(sub {
				shift;
				cmp_deeply [@_], [$read_files_mode, $options->{'max-number-of-files'}];
			})->once;
			App::MtAws::Journal->expects("open_for_write")->returns_ordered->once;
		}
		
		sub expect_fork_engine
		{
			App::MtAws::SyncCommand->expects("fork_engine")->returns_ordered(sub {
				bless { parent_worker =>
					bless {}, 'App::MtAws::ParentWorker'
				}, 'App::MtAws::ForkEngine';
			})->once;
		}
		
		sub expect_journal_close
		{
			App::MtAws::Journal->expects("close_for_write")->returns_ordered->once;
		}
		
		sub expect_process_task
		{
			my ($j, $cb) = @_;
			App::MtAws::ParentWorker->expects("process_task")->returns_ordered(sub {
				my ($self, $job, $journal) = @_;
				ok $self->isa('App::MtAws::ParentWorker');
				is $journal, $j;
				$cb->($job);
			} )->once;
		}
		
		it "should work with new" => sub {
			my $options = { 'max-number-of-files' => 10, partsize => 2, new => 1 };
			ordered_test sub {
				expect_with_forks;
				expect_journal_init($options, {new=>1});
				expect_fork_engine;
				my @files = qw/file1 file2 file3 file4/;
	
				expect_process_task($j, sub {
					my ($job) = @_;
					ok $job->isa('App::MtAws::JobListProxy');
					is scalar @{ $job->{jobs} }, 1;
					my $itt = $job->{jobs}[0];
					for (@files) {
						my $task = $itt->{iterator}->();
						is $task->{job}{relfilename}, $_;
						is $task->{job}{partsize}, $options->{partsize}*1024*1024;
						ok $task->isa('App::MtAws::JobProxy');
						ok $task->{job}->isa('App::MtAws::FileCreateJob');
					}
					return (1)
				});
	
				expect_journal_close;
				$j->{listing}{existing} = [];
				$j->{listing}{new} = [ map { { relfilename => $_ }} @files ];
				
				App::MtAws::SyncCommand::run($options, $j);
			};
		};
		
		it "should work with replace-modified" => sub {
			my $options = { 'max-number-of-files' => 10, partsize => 2, 'replace-modified' => 1, detect => 'mtime-and-treehash' };
			ordered_test sub {
				expect_with_forks;
				expect_journal_init($options, {existing=>1});
				expect_fork_engine;
				my %files = (
					file1 => {size => 123},
					file2 => {size => 456},
					file3 => {size => 789},
					file4 => {size => 42}
				);
	
				expect_process_task($j, sub {
					my ($job) = @_;
					ok $job->isa('App::MtAws::JobListProxy');
					is scalar @{ $job->{jobs} }, 1;
					my $itt = $job->{jobs}[0];
					for (sort keys %files) {
						my $task = $itt->{iterator}->();
						is $task->{job}{relfilename}, $_;
						is $task->{job}{partsize}, $options->{partsize}*1024*1024;
						ok $task->isa('App::MtAws::JobProxy');
						ok $task->{job}->isa('App::MtAws::FileCreateJob');
					}
					return (1)
				});
	
				expect_journal_close;
				$j->{listing}{new} = [];
				for (sort keys %files) {
					my $r = {relfilename => $_, size => $files{$_}{size}};
					$j->_add_filename($r);
					push @{ $j->{listing}{existing} }, $r;
				}
				App::MtAws::SyncCommand->expects("file_size")->returns(sub {
					my ($file) = @_;
					$file =~ m!([^/]+)$! or confess;
					$files{$1}{size}+1 or confess;
				})->exactly(scalar keys %files);
				
				App::MtAws::SyncCommand::run($options, $j);
			};
		};
	}
};

runtests unless caller;

1;
