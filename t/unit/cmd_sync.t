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

use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";

use Carp;
use List::Util qw/first/;
use Scalar::Util qw/looks_like_number/;

use Test::Spec 0.46;
use Test::More tests => 455;
use Test::Deep;

use Data::Dumper;
use TestUtils;

use App::MtAws::Journal;
require App::MtAws::SyncCommand;

warning_fatal();

describe "command" => sub {
	my $j;
	
	before each => sub {
		$j = App::MtAws::Journal->new(journal_file => 'x', 'root_dir' => 'x' );
	};
		
	describe "modified processing" => sub {
		
		my @all_detect = qw/treehash mtime mtime-and-treehash mtime-or-treehash/; # TODO: fetch from ConfigDefinition
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
			it "should work when mtime is undefined in journal" => sub {
				App::MtAws::SyncCommand->expects("file_mtime")->never;
				ok !App::MtAws::SyncCommand::is_mtime_differs({detect => 'mtime-and-treehash'},{mtime => undef}, 'file1');
			};
			it "should work when detect contains mtime" => sub {
				for (@detect_with_mtime) {
					App::MtAws::SyncCommand->expects("file_mtime")->returns(sub{ is shift, 'file1'; 42;})->once;
					ok App::MtAws::SyncCommand::is_mtime_differs({detect => $_},{mtime => 123}, 'file1');
				}
			};
			it "should work when detect does not contain mtime" => sub {
				for (@detect_without_mtime) {
					App::MtAws::SyncCommand->expects("file_mtime")->never;
					ok ! defined App::MtAws::SyncCommand::is_mtime_differs({detect => $_},{mtime => 123}, 'file1');
				}
			};
		};
		
		describe "should_upload" => sub {
			
			it "should define unique constants" => sub {
				ok App::MtAws::SyncCommand::SHOULD_CREATE() != App::MtAws::SyncCommand::SHOULD_TREEHASH();
				ok App::MtAws::SyncCommand::SHOULD_CREATE() != App::MtAws::SyncCommand::SHOULD_NOACTION();
				
				ok App::MtAws::SyncCommand::SHOULD_CREATE();
				ok App::MtAws::SyncCommand::SHOULD_TREEHASH();
				ok !App::MtAws::SyncCommand::SHOULD_NOACTION(); # one should be FALSE
				
				# numeric eq only
				ok looks_like_number App::MtAws::SyncCommand::SHOULD_CREATE();
				ok looks_like_number App::MtAws::SyncCommand::SHOULD_TREEHASH();
				ok looks_like_number App::MtAws::SyncCommand::SHOULD_NOACTION();
			};
			
			it "should always return create if file size differs" => sub {
				for (@all_detect) {
					App::MtAws::SyncCommand->expects("is_mtime_differs")->never;
					App::MtAws::SyncCommand->expects("file_size")->returns(42)->once;
					is  App::MtAws::SyncCommand::should_upload({detect => $_},{mtime => 123, size => 43}, 'file1'),
						App::MtAws::SyncCommand::SHOULD_CREATE();
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
					test_should_upload('mtime', 1, 1, App::MtAws::SyncCommand::SHOULD_CREATE());
				};
				it "should return FALSE when mtime same" => sub {
					test_should_upload('mtime', 0, 1, App::MtAws::SyncCommand::SHOULD_NOACTION());
				};
			};

			describe "detect=treehash" => sub {
				it "should return 'treehash' mtime is irrelevant" => sub {
					test_should_upload('treehash', $_, 0, App::MtAws::SyncCommand::SHOULD_TREEHASH()) for (0,1);
				};
			};

			describe "detect=mtime-and-treehash" => sub {
				it "should return 'treehash' when mtime differs" => sub {
					test_should_upload('mtime-and-treehash', 1, 1, App::MtAws::SyncCommand::SHOULD_TREEHASH());
				};
				it "should return FALSE when mtime same" => sub {
					test_should_upload('mtime-and-treehash', 0, 1, App::MtAws::SyncCommand::SHOULD_NOACTION());
				};
			};
			
			describe "detect=mtime-or-treehash" => sub {
				it "should return 'create' when mtime differs" => sub {
					test_should_upload('mtime-or-treehash', 1, 1, App::MtAws::SyncCommand::SHOULD_CREATE());
				};
				it "should return 'treehash' when mtime same" => sub {
					test_should_upload('mtime-or-treehash', 0, 1, App::MtAws::SyncCommand::SHOULD_TREEHASH());
				};
			};
			
			describe "detect is unknown" => sub {
				my $file = {mtime => 123, size => 42};
				App::MtAws::SyncCommand->expects("file_size")->returns(42)->once;
				ok ! defined eval { App::MtAws::SyncCommand::should_upload({detect => 'xyz'}, $file, 'file1'); 1; };
				ok $@ =~ /Invalid detect option in should_upload/;
			} 
		};
		
		describe "next_modified" => sub {
			my $options;
			before each => sub {
				$options = { partsize => 2};
			};
			
			sub expect_should_upload
			{
				my ($options, $j, $file, $toreturn) = @_;
				App::MtAws::SyncCommand->expects("should_upload")->returns(sub {
					my ($opt, $f, $absfilename) = @_;
					cmp_deeply $opt, $options;
					cmp_deeply $f, $file;
					is $absfilename, $j->absfilename($file->{relfilename});
					return $toreturn;
				})->once;
			}
			
			sub verify_create_job
			{
				my ($options, $j, $file, $rec) = @_;
				ok $rec->isa('App::MtAws::JobProxy');
				my $job = $rec->{job};
				ok $job->isa('App::MtAws::FileCreateJob');
				is $job->{partsize}, $options->{partsize}*1024*1024;
				is $job->{relfilename}, $file->{relfilename};
				is $job->{filename}, $j->absfilename($file->{relfilename});
				
				is ref $job->{finish_cb}, 'CODE';
				
				my $finish = $job->{finish_cb}->();
				
				ok $finish->isa('App::MtAws::FileListDeleteJob');
				cmp_deeply $finish->{archives}, [{archive_id => $file->{archive_id}, relfilename => $file->{relfilename}}];
			}
			
			sub verify_treehash_job
			{
				my ($options, $j, $file, $rec) = @_;
				ok $rec->isa('App::MtAws::JobProxy');
				my $job = $rec->{job};
				ok $job->isa('App::MtAws::FileVerifyAndUploadJob');
				is $job->{filename}, $j->absfilename($file->{relfilename});
				is $job->{relfilename}, $file->{relfilename};
				ok $job->{delete_after_upload};
				is $job->{archive_id}, $file->{archive_id};
				is $job->{treehash}, $file->{treehash};
				is $job->{partsize}, $options->{partsize}*1024*1024;
			}
			

			it "should work with zero files" => sub {
				$j->{listing}{existing} = [];
				ok !defined App::MtAws::SyncCommand::next_modified($options, $j);
			};

			it "should work when should_upload returns SHOULD_CREATE" => sub {
				my $file = {relfilename => 'file1', archive_id => 'zz1'};
				$j->{listing}{existing} = [$file];
				$j->_add_filename($file);
				expect_should_upload($options, $j, $file, App::MtAws::SyncCommand::SHOULD_CREATE());
				my $rec = App::MtAws::SyncCommand::next_modified($options, $j);
				verify_create_job($options, $j, $file, $rec);

				is scalar @{ $j->{listing}{existing} }, 0;
				ok !defined (App::MtAws::SyncCommand::next_modified($options, $j)); 
			};

			it "should work with two files" => sub {
				my $file1 = {relfilename => 'file1', archive_id => 'zz1'};
				my $file2 = {relfilename => 'file2', archive_id => 'zz2'};
				$j->{listing}{existing} = [$file1, $file2];
				$j->_add_filename($file1);
				$j->_add_filename($file2);
				expect_should_upload($options, $j, $file1, App::MtAws::SyncCommand::SHOULD_CREATE());
				my $rec = App::MtAws::SyncCommand::next_modified($options, $j);
				verify_create_job($options, $j, $file1, $rec);

				is scalar @{ $j->{listing}{existing} }, 1;

				expect_should_upload($options, $j, $file2, App::MtAws::SyncCommand::SHOULD_CREATE());
				$rec = App::MtAws::SyncCommand::next_modified($options, $j);
				verify_create_job($options, $j, $file2, $rec);
			};

			it "should work with latest version of file" => sub {
				my $file = {relfilename => 'file1', size => 123};
				$j->{listing}{existing} = [$file];
				$j->_add_filename({relfilename => 'file1', archive_id => 'zz1', size => 123, time => 42, mtime => 111, , treehash => 'abc0'});
				$j->_add_filename(my $r = {relfilename => 'file1', archive_id => 'zz2', size => 123, time => 42, mtime => 113, treehash => 'abc'});
				$j->_add_filename({relfilename => 'file1', archive_id => 'zz3', size => 123, time => 42, mtime => 112, , treehash => 'abc2'});
				expect_should_upload($options, $j, $r, App::MtAws::SyncCommand::SHOULD_TREEHASH());
				my $rec = App::MtAws::SyncCommand::next_modified($options, $j);
				verify_treehash_job($options, $j, $r, $rec);
				is scalar @{ $j->{listing}{existing} }, 0;
			};
			
			it "should call latest() to get latest version of file" => sub {
				my $file = {relfilename => 'file1', size => 123};
				$j->{listing}{existing} = [$file];
				$j->_add_filename({relfilename => 'file1', archive_id => 'zz1', size => 123, time => 42, mtime => 111, , treehash => 'abc0'});
				$j->_add_filename(my $r = {relfilename => 'file1', archive_id => 'zz2', size => 123, time => 42, mtime => 113, treehash => 'abc'});
				$j->_add_filename({relfilename => 'file1', archive_id => 'zz3', size => 123, time => 42, mtime => 112, , treehash => 'abc2'});
				expect_should_upload($options, $j, $r, App::MtAws::SyncCommand::SHOULD_TREEHASH());
				App::MtAws::Journal->expects("latest")->with('file1')->returns($r)->once;
				App::MtAws::SyncCommand::next_modified($options, $j);
			};

			it "should work when should_upload returns SHOULD_TREEHASH" => sub {
				my $file = {relfilename => 'file1', archive_id => 'zz1', treehash => 'abcdef'};
				$j->{listing}{existing} = [$file];
				$j->_add_filename($file);
				expect_should_upload($options, $j, $file, App::MtAws::SyncCommand::SHOULD_TREEHASH());
				my $rec = App::MtAws::SyncCommand::next_modified($options, $j);
				verify_treehash_job($options, $j, $file, $rec);

				is scalar @{ $j->{listing}{existing} }, 0;
				ok !defined (App::MtAws::SyncCommand::next_modified($options, $j)); 
			};

			it "should skip to next file when should_upload returns SHOULD_NOACTION" => sub {
				for (1..10) {
					my $file = {relfilename => "file$_", archive_id => "zz$_"};
					push @{ $j->{listing}{existing} }, $file;
					$j->_add_filename($file);
				}
				
				my $file;
				App::MtAws::SyncCommand->expects("should_upload")->returns(sub {
					my ($opt, $f, $absfilename) = @_;
					$file = $f;
					return $f->{relfilename} eq 'file7' ? App::MtAws::SyncCommand::SHOULD_CREATE() : App::MtAws::SyncCommand::SHOULD_NOACTION();
				})->exactly(10);
				
				my $rec = App::MtAws::SyncCommand::next_modified($options, $j);
				verify_create_job($options, $j, $file, $rec);

				is scalar @{ $j->{listing}{existing} }, 3;
				ok !defined App::MtAws::SyncCommand::next_modified($options, $j);
			};

			it "should confess when should_upload returns something else" => sub {
				my $file = {relfilename => 'file1', archive_id => 'zz1'};
				$j->{listing}{existing} = [$file];
				$j->_add_filename($file);
				expect_should_upload($options, $j, $file, 7656348);
				ok !defined eval{ App::MtAws::SyncCommand::next_modified($options, $j); 1};
				ok $@ =~ /Unknown value returned by should_upload/;
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

	describe "get_journal_opts" => sub {
		it "should work in all cases" => sub {
			for my $n (0, 1) {
				for my $r (0, 1) {
					for my $d (0, 1) {
						my $options = {};
						$options->{new} = 1 if $n;
						$options->{'replace-modified'} = 1 if $r;
						$options->{'delete-removed'} = 1 if $d;
						my $res = App::MtAws::SyncCommand::get_journal_opts($options);
						ok ! first { !/^(new|existing|missing)$/ } keys %$res; # make sure we don't have other keys here
						cmp_deeply $res->{new}, bool $n; # can be 0, undef, not existant etc
						cmp_deeply $res->{existing}, bool $r;
						cmp_deeply $res->{missing}, bool $d;
					}
				}
			}
		};
	};

	describe "print_dry_run" => sub {
		{
			package WillDoTest;
			use Carp;
			sub will_do {
				my ($self) = @_;
				if ($self->{toprint_a}) {
				 	map { "Will ".$_ } @{ $self->{toprint_a} };
				} elsif ($self->{toprint}) {
					"Will ".$self->{toprint};
				} elsif ($self->{empty}) {
					''
				} else {
					return;
				}
			}
		}
		it "should work with zero elements" => sub {
			my $out = '';
			capture_stdout $out => sub {
				App::MtAws::SyncCommand::print_dry_run(sub {});
			};
			is $out, "";
		};
		it "should work with one element when it returns empty list" => sub {
			my @a = bless {}, "WillDoTest";
			my $out = '';
			capture_stdout $out => sub {
				App::MtAws::SyncCommand::print_dry_run(sub { shift @a });
			};
			is $out, "";
		};
		it "should work with one element when it returns empty string" => sub {
			my @a = bless {empty=>'1'}, "WillDoTest";
			my $out = '';
			capture_stdout $out => sub {
				App::MtAws::SyncCommand::print_dry_run(sub { shift @a });
			};
			is $out, "\n";
		};
		it "should work with one element" => sub {
			my @a = bless { toprint => 42}, "WillDoTest";
			my $out = '';
			capture_stdout $out => sub {
				App::MtAws::SyncCommand::print_dry_run(sub { shift @a });
			};
			is $out, "Will 42\n";
		};
		it "should work with two elements" => sub {
			my @a = (bless({ toprint => 42}, "WillDoTest"),bless({ toprint => 123}, "WillDoTest"));
			my $out = '';
			capture_stdout $out => sub {
				App::MtAws::SyncCommand::print_dry_run(sub { shift @a });
			};
			is $out, "Will 42\nWill 123\n";
		};
		it "should work with list elements" => sub {
			my @a = bless { toprint_a => [42, 'zz']}, "WillDoTest";
			my $out = '';
			capture_stdout $out => sub {
				App::MtAws::SyncCommand::print_dry_run(sub { shift @a });
			};
			is $out, "Will 42\nWill zz\n";
		};
		it "should work with two list elements" => sub {
			my @a = ( bless({ toprint_a => [42, 'zz']}, "WillDoTest"),  bless({ toprint_a => [123, 'ff']}, "WillDoTest"));
			my $out = '';
			capture_stdout $out => sub {
				App::MtAws::SyncCommand::print_dry_run(sub { shift @a });
			};
			is $out, "Will 42\nWill zz\nWill 123\nWill ff\n";
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
		
		it "should work with delete-removed" => sub {
			my $options = { 'max-number-of-files' => 10, partsize => 2, 'delete-removed' => 1 };
			ordered_test sub {
				expect_with_forks;
				expect_journal_init($options, {missing=>1});
				expect_fork_engine;
				my %files = (
					file1 => {archive_id => 'z123'},
					file2 => {archive_id => 'z456'},
					file3 => {archive_id => 'z789'},
					file4 => {archive_id => 'z42'}
				);
	
				expect_process_task($j, sub {
					my ($job) = @_;
					ok $job->isa('App::MtAws::JobListProxy');
					is scalar @{ $job->{jobs} }, 1;
					my $itt = $job->{jobs}[0];
					for (sort keys %files) {
						my $task = $itt->{iterator}->();
						ok $task->isa('App::MtAws::FileListDeleteJob');
						is scalar @{ $task->{archives} }, 1;
						my $a = $task->{archives}[0];
						is $a->{relfilename}, $_;
						is $a->{archive_id}, $files{$_}{archive_id};
					}
					return (1)
				});
	
				expect_journal_close;
				$j->{listing}{missing} = [];
				for (sort keys %files) {
					my $r = {relfilename => $_, archive_id => $files{$_}{archive_id}};
					$j->_add_filename($r);
					push @{ $j->{listing}{missing} }, $r;
				}
				
				App::MtAws::SyncCommand::run($options, $j);
			};
		};

		it "should work with combination of options" => sub {
			for my $n (0, 1) { for my $r (0, 1) { for my $d (0, 1) {
				my $options = {
					'max-number-of-files' => 10, partsize => 2,
					$n ? (new => 1) : (),
					$r ? ('replace-modified' => 1, detect => 'mtime-or-treehash') : (),
					$d ? ('delete-removed' => 1) : (),
				};
				ordered_test sub {
					expect_with_forks;
					expect_journal_init($options, App::MtAws::SyncCommand::get_journal_opts($options));
					
					my @files = qw/file1 file2 file3 file4/;
					
					{
						my $res = App::MtAws::SyncCommand->expects("next_new")->returns("sub_next_new");
						$n ? $res->once : $res->never;
					}
					{
						my $res = App::MtAws::SyncCommand->expects("next_modified")->returns("sub_next_modified");
						$r ? $res->once : $res->never;
					}
					{
						my $res = App::MtAws::SyncCommand->expects("next_missing")->returns("sub_next_missing");
						$d ? $res->once : $res->never;
					}
					if ($n || $r || $d) {
						expect_fork_engine;
						expect_process_task($j, sub {
							my ($job) = @_;
							ok $job->isa('App::MtAws::JobListProxy');
							cmp_deeply [ map { $_->{iterator}->() } @{ $job->{jobs} } ], [
								$n ? ('sub_next_new') : (),
								$r ? ('sub_next_modified') : (),
								$d ? ('sub_next_missing') : (),
							];
							return (1);
						});
					} else {
						App::MtAws::SyncCommand->expects("fork_engine")->never;
						App::MtAws::ParentWorker->expects("process_task")->never;
						ok 1; # test that we got there, just in case
					}
		
					expect_journal_close;
					
					App::MtAws::SyncCommand::run($options, $j);
				};
			}}}
		};
		
		it "should work with combination of options in dry-run mode" => sub {
			for my $n (0, 1) { for my $r (0, 1) { for my $d (0, 1) {
				my $options = {
					'max-number-of-files' => 10, partsize => 2, 'dry-run' => 1,
					$n ? (new => 1) : (),
					$r ? ('replace-modified' => 1, detect => 'mtime-or-treehash') : (),
					$d ? ('delete-removed' => 1) : (),
				};
				ordered_test sub {
					expect_with_forks;
					expect_journal_init($options, App::MtAws::SyncCommand::get_journal_opts($options));
					
					{
						my $res = App::MtAws::SyncCommand->expects("next_new")->returns("sub_next_new");
						$n ? $res->once : $res->never;
					}
					{
						my $res = App::MtAws::SyncCommand->expects("next_modified")->returns("sub_next_modified");
						$r ? $res->once : $res->never;
					}
					{
						my $res = App::MtAws::SyncCommand->expects("next_missing")->returns("sub_next_missing");
						$d ? $res->once : $res->never;
					}
					
					my @dry_run_args;
					App::MtAws::SyncCommand->expects("print_dry_run")->returns(sub {
						push @dry_run_args, shift;
					})->any_number;
					
					App::MtAws::SyncCommand->expects("fork_engine")->never;
					App::MtAws::ParentWorker->expects("process_task")->never;
		
					expect_journal_close;
					
					App::MtAws::SyncCommand::run($options, $j);
					
					cmp_deeply [ map { $_->() } @dry_run_args ], [
						$n ? ('sub_next_new') : (),
						$r ? ('sub_next_modified') : (),
						$d ? ('sub_next_missing') : (),
					];
				};
			}}}
		}
	}
};

runtests unless caller;

1;
