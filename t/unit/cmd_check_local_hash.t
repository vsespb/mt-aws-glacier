#!/usr/bin/env perl

# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2014  Victor Efimov
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
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';

use Carp;
use POSIX;

use Test::Spec;
use Test::More tests => 242;
use Test::Deep;

use Data::Dumper;

use App::MtAws::Journal;
use App::MtAws::Exceptions;

sub _close { CORE::close($_[0]) };
BEGIN { *CORE::GLOBAL::close = sub(;*) { _close($_[0]) }; };


require App::MtAws::Command::CheckLocalHash;




sub parse_out
{
	my %res;
	for (shift) {
		($res{ok}) = /^(\d) OK$/m and
		($res{mtime}) = /^(\d) MODIFICATION TIME MISSMATCHES$/m and
		($res{treehash}) = /^(\d) TREEHASH MISSMATCH$/m and
		($res{size}) = /^(\d) SIZE MISSMATCH$/m and
		($res{zero}) = /^(\d) ZERO SIZE$/m and
		($res{missed}) = /^(\d) MISSED$/m and
		($res{errors}) = /^(\d) ERRORS$/m or confess;
	}
	%res;
}

describe "command" => sub {
	my $j;
	my $options;
	my $file1 = {size => 123, treehash => 'zz123', mtime => 456, relfilename => 'file1'};

	before each => sub {
		$j = App::MtAws::Journal->new(journal_file => 'x', 'root_dir' => 'x' );
		$options = {};
	};

	describe "check_local_hash" => sub {

		sub expect_read_journal
		{
			my ($j, @files) = @_;
			$j->expects("read_journal")->returns_ordered(sub {
				shift;
				cmp_deeply({@_}, {should_exist => 1});
			})->once;
			$j->{journal_h} = { map { $_->{relfilename} => $_} @files };
		}

		sub expect_file_exists
		{
			my ($filename, $res) = (@_, 1);
			App::MtAws::Command::CheckLocalHash->expects("file_exists")->returns_ordered(sub {
				like shift, qr/\Q$filename\E$/;
				$res;
			});
		}

		sub expect_file_size
		{
			my ($filename, $res) = @_;
			App::MtAws::Command::CheckLocalHash->expects("file_size")->returns_ordered(sub {
				like shift, qr/\Q$filename\E$/;
				$res;
			});
		}

		sub expect_file_mtime
		{
			my ($filename, $res) = @_;
			App::MtAws::Command::CheckLocalHash->expects("file_mtime")->returns_ordered(sub {
				like shift, qr/\Q$filename\E$/;
				$res;
			});
		}

		sub expect_open_file
		{
			my ($file, $filename, $res, $err) = @_;
			App::MtAws::Command::CheckLocalHash->expects("open_file")->returns_ordered(sub {
				$_[0] = $file;
				my (undef, $fn, %o) = @_;
				like $fn, qr/\Q$filename\E$/;
				cmp_deeply { %o }, { mode => '<', binary => 1 };
				$! = $err if ($err);
				$res;
			});
		}

		sub expect_treehash
		{
			my ($file, $res) = @_;
			my $treehash_mock = bless {}, 'App::MtAws::TreeHash';
			App::MtAws::TreeHash->expects("new")->returns_ordered($treehash_mock);
			$treehash_mock->expects("eat_file")->returns_ordered(sub {
				cmp_deeply [@_], [$treehash_mock, $file];
			});
			$treehash_mock->expects("calc_tree")->returns_ordered(0);
			$treehash_mock->expects("get_final_hash")->returns_ordered($res);
		}

		sub run_command
		{
			my ($options, $j, $close_res) = (@_, 1);
			my $res = capture_stdout my $out => sub {
				no warnings 'redefine';
				local *_close = sub { $close_res };
				return eval { App::MtAws::Command::CheckLocalHash::run($options, $j); 1 };
			};
			return ($res, $out);
		}

		sub check_ok
		{
			my ($out, @failures) = @_;
			my %results = parse_out($out);
			is delete $results{$_}, 1, "$_=1" for (@failures);
			is $results{$_}, 0, "$_=0" for (keys %results);
		}

		it "should work when everything matches" => sub {
			ordered_test sub {
				expect_read_journal $j, $file1;

				expect_file_exists $file1->{relfilename};
				expect_file_size $file1->{relfilename}, $file1->{size};
				expect_file_mtime $file1->{relfilename}, $file1->{mtime};
				expect_open_file my $fileobj = { mock => 1 }, $file1->{relfilename}, 1;
				expect_treehash $fileobj, $file1->{treehash};

				my ($res, $out) = run_command($options, $j);
				ok $res;
				ok $out =~ /^OK file1 $file1->{size} $file1->{treehash}$/m;
				check_ok($out, qw/ok/);
			};
		};
		describe "latest()" => sub {
			it "should work with latest file when everything matches" => sub {
				ordered_test sub {
					expect_read_journal $j;
					$j->_add_filename({size => 1231, treehash => 'th001', mtime => 4000, relfilename => 'file1'});
					$j->_add_filename(my $r = {size => 1232, treehash => 'th002', mtime => 4003, relfilename => 'file1'});
					$j->_add_filename({size => 1233, treehash => 'th003', mtime => 4001, relfilename => 'file1'});
					expect_file_exists $r->{relfilename};
					expect_file_size $r->{relfilename}, $r->{size};
					expect_file_mtime $r->{relfilename}, $r->{mtime};
					expect_open_file my $fileobj = { mock => 1 }, $r->{relfilename}, 1;
					expect_treehash $fileobj, $r->{treehash};

					my ($res, $out) = run_command($options, $j);
					ok $res;
					ok $out =~ /^OK file1 $r->{size} $r->{treehash}$/m;
					check_ok($out, qw/ok/);
				};
			};
			it "should work with latest file and call latest() when everything matches" => sub {
				ordered_test sub {
					expect_read_journal $j;
					$j->_add_filename({size => 1231, treehash => 'th001', mtime => 4000, relfilename => 'file1'});
					$j->_add_filename(my $r = {size => 1232, treehash => 'th002', mtime => 4003, relfilename => 'file1'});
					$j->_add_filename({size => 1233, treehash => 'th003', mtime => 4001, relfilename => 'file1'});
					App::MtAws::Journal->expects("latest")->returns_ordered(sub{ is $_[1], "file1"; $r})->once;
					expect_file_exists $r->{relfilename};
					expect_file_size $r->{relfilename}, $r->{size};
					expect_file_mtime $r->{relfilename}, $r->{mtime};
					expect_open_file my $fileobj = { mock => 1 }, $r->{relfilename}, 1;
					expect_treehash $fileobj, $r->{treehash};

					my ($res, $out) = run_command($options, $j);
					ok $res;
					ok $out =~ /^OK file1 $r->{size} $r->{treehash}$/m;
					check_ok($out, qw/ok/);
				};
			};
		};
		it "should work when treehash does not match" => sub {
			ordered_test sub {
				expect_read_journal $j, $file1;

				expect_file_exists $file1->{relfilename};
				expect_file_size $file1->{relfilename}, $file1->{size};
				expect_file_mtime $file1->{relfilename}, $file1->{mtime};
				expect_open_file my $fileobj = { mock => 1 }, $file1->{relfilename}, 1;
				expect_treehash $fileobj, "not_a_treehash";

				my ($res, $out) = run_command($options, $j);
				ok !$res;
				ok $out =~ /^TREEHASH MISSMATCH file1$/m;
				check_ok($out, qw/treehash/);
			};
		};
		it "should work when mtime does not match" => sub {
			ordered_test sub {
				expect_read_journal $j, $file1;

				expect_file_exists $file1->{relfilename};
				expect_file_size $file1->{relfilename}, $file1->{size};
				expect_file_mtime $file1->{relfilename}, $file1->{mtime}+1;
				expect_open_file my $fileobj = { mock => 1 }, $file1->{relfilename}, 1;
				expect_treehash $fileobj, $file1->{treehash};

				my ($res, $out) = run_command($options, $j);
				ok $res;
				ok $out =~ /^OK file1 $file1->{size} $file1->{treehash}$/m;
				check_ok($out, qw/ok mtime/);
			};
		};
		it "should work when size does not match" => sub {
			ordered_test sub {
				expect_read_journal $j, $file1;

				expect_file_exists $file1->{relfilename};
				expect_file_size $file1->{relfilename}, $file1->{size}+1;
				expect_file_mtime $file1->{relfilename}, $file1->{mtime};
				App::MtAws::Command::CheckLocalHash->expects("open_file")->never;
				App::MtAws::TreeHash->expects("new")->never;

				my ($res, $out) = run_command($options, $j);
				ok !$res;
				ok $out =~ /^SIZE MISSMATCH file1$/m;
				check_ok($out, qw/size/);
			};
		};
		it "should work when size is zero" => sub {
			ordered_test sub {
				expect_read_journal $j, $file1;

				expect_file_exists $file1->{relfilename};
				expect_file_size $file1->{relfilename}, 0;
				expect_file_mtime $file1->{relfilename}, $file1->{mtime};
				App::MtAws::Command::CheckLocalHash->expects("open_file")->never;
				App::MtAws::TreeHash->expects("new")->never;

				my ($res, $out) = run_command($options, $j);
				ok !$res;
				ok $out =~ /^ZERO SIZE file1$/m;
				check_ok($out, qw/zero/);
			};
		};
		it "should work when file is not exists" => sub {
			ordered_test sub {
				expect_read_journal $j, $file1;

				expect_file_exists $file1->{relfilename}, 0;
				App::MtAws::Command::CheckLocalHash->expects("file_size")->never;
				App::MtAws::Command::CheckLocalHash->expects("file_mtime")->never;
				App::MtAws::Command::CheckLocalHash->expects("open_file")->never;
				App::MtAws::TreeHash->expects("new")->never;

				my ($res, $out) = run_command($options, $j);
				ok !$res;
				ok $out =~ /^MISSED file1$/m;
				check_ok($out, qw/missed/);
			};
		};
		it "should never check mtime if it does not exist" => sub {
			ordered_test sub {
				my $file2 = {size => 1234, treehash => 'zz123ff', mtime => undef, relfilename => 'file2'};
				expect_read_journal $j, $file2;

				expect_file_exists $file2->{relfilename};
				expect_file_size $file2->{relfilename}, $file2->{size};
				App::MtAws::Command::CheckLocalHash->expects("file_mtime")->never;
				expect_open_file my $fileobj = { mock => 1 }, $file2->{relfilename}, 1;
				expect_treehash $fileobj, $file2->{treehash};

				my ($res, $out) = run_command($options, $j);
				ok $res;
				ok $out =~ /^OK file2 $file2->{size} $file2->{treehash}$/m;
				check_ok($out, qw/ok/);
			};
		};
		it "should work when file open error happens" => sub {
			ordered_test sub {
				expect_read_journal $j, $file1;

				expect_file_exists $file1->{relfilename};
				expect_file_size $file1->{relfilename}, $file1->{size};
				expect_file_mtime $file1->{relfilename}, $file1->{mtime};
				expect_open_file my $fileobj = { mock => 1 }, $file1->{relfilename}, 0, EACCES;
				App::MtAws::TreeHash->expects("new")->never;

				my ($res, $out) = run_command($options, $j);
				ok !$res;
				my $estr = get_errno(strerror(EACCES));
				ok $out =~ /^CANNOT OPEN file file1: $estr$/m;
				check_ok($out, qw/errors/);
			};
		};
		it "should confess when close return error" => sub {
			ordered_test sub {
				expect_read_journal $j, $file1;

				expect_file_exists $file1->{relfilename};
				expect_file_size $file1->{relfilename}, $file1->{size};
				expect_file_mtime $file1->{relfilename}, $file1->{mtime};
				expect_open_file my $fileobj = { mock => 1 }, $file1->{relfilename}, 1;

				my $treehash_mock = bless {}, 'App::MtAws::TreeHash';
				App::MtAws::TreeHash->expects("new")->returns_ordered($treehash_mock);
				$treehash_mock->expects("eat_file")->returns_ordered(sub {
					cmp_deeply [@_], [$treehash_mock, $fileobj];
				});
				$treehash_mock->expects("calc_tree")->never;
				$treehash_mock->expects("get_final_hash")->never;

				my ($res, $out) = run_command($options, $j, 0);
				ok !$res;
			};
		};
		it "should work with dry-run" => sub {
			ordered_test sub {
				$options->{'dry-run'} = 1;
				expect_read_journal $j, $file1;

				App::MtAws::Command::CheckLocalHash->expects("file_exists")->never;
				App::MtAws::Command::CheckLocalHash->expects("file_size")->never;
				App::MtAws::Command::CheckLocalHash->expects("file_mtime")->never;
				App::MtAws::Command::CheckLocalHash->expects("open_file")->never;
				App::MtAws::TreeHash->expects("new")->never;

				my ($res, $out) = run_command($options, $j);
				ok $res;
				ok $out =~ /^Will check file file1$/m;
				unlike $out, qr/TREEHASH/;
				unlike $out, qr/OK/;
			};
		};
		it "should work with several files" => sub {
			ordered_test sub {
				my @files = (
					{size => 123, treehash => 'zz123', mtime => 456, relfilename => 'file1'},
					{size => 1231, treehash => 'zz123', mtime => 4561, relfilename => 'file2'},
					{size => 1232, treehash => 'zz123', mtime => 4562, relfilename => 'file3'},
				);
				my %files_h = map { $_->{relfilename} => $_ } @files;
				expect_read_journal $j, @files;

				App::MtAws::Command::CheckLocalHash->expects("file_exists")->returns(1)->exactly(scalar @files);
				App::MtAws::Command::CheckLocalHash->expects("file_size")->returns(sub {
					shift =~ m!([^/]+)$!;
					$files_h{$1}->{size}
				})->exactly(scalar @files);
				App::MtAws::Command::CheckLocalHash->expects("file_mtime")->returns(sub {
					shift =~ m!([^/]+)$!;
					$files_h{$1}->{mtime}
				})->exactly(scalar @files);
				App::MtAws::Command::CheckLocalHash->expects("open_file")->returns(sub {
					$_[1] =~ m!([^/]+)$!;
					$_[0] = { mock => $files_h{$1}->{relfilename} };
					1;
				})->exactly(scalar @files);
				my $treehash_mock = bless {}, 'App::MtAws::TreeHash';
				App::MtAws::TreeHash->expects("new")->returns($treehash_mock)->exactly(scalar @files);
				$treehash_mock->expects("eat_file")->exactly(scalar @files);
				$treehash_mock->expects("calc_tree")->exactly(scalar @files);
				$treehash_mock->expects("get_final_hash")->returns('zz123')->exactly(scalar @files);

				my ($res, $out) = run_command($options, $j);
				ok $res;
				ok $out =~ /^3 OK$/m;
			};
		};
	};
};

runtests unless caller;

1;
