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
#use Test::More tests => 455;
use Test::Deep;

use Data::Dumper;
use TestUtils;

use App::MtAws::Journal;

sub _close { CORE::close($_[0]) };
BEGIN { *CORE::GLOBAL::close = sub(;*) { _close($_[0]) }; };


require App::MtAws::CheckLocalHashCommand;


warning_fatal();

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

	before each => sub {
		$j = App::MtAws::Journal->new(journal_file => 'x', 'root_dir' => 'x' );
		$options = {};
	};

	describe "check_local_hash" => sub {

		sub expect_file_exists
		{
			App::MtAws::CheckLocalHashCommand->expects("file_exists")->returns_ordered(1);
		}

		sub expect_file_size
		{
				App::MtAws::CheckLocalHashCommand->expects("file_size")->returns_ordered(shift);
		}

		sub expect_file_mtime
		{
				App::MtAws::CheckLocalHashCommand->expects("file_mtime")->returns_ordered(shift);
		}

		sub expect_open_file
		{
			App::MtAws::CheckLocalHashCommand->expects("open_file")->returns_ordered(sub {
				$_[0] = {};
			});
		}

		sub expect_treehash
		{
			my $treehash_mock = bless {}, 'App::MtAws::TreeHash';
			App::MtAws::TreeHash->expects("new")->returns_ordered($treehash_mock);
			$treehash_mock->expects("eat_file")->returns_ordered(0);
			$treehash_mock->expects("calc_tree")->returns_ordered(0);
			$treehash_mock->expects("get_final_hash")->returns_ordered(shift);
		}

		sub run_command
		{
			my ($options, $j) = @_;
			my $out = '';
			my $res = capture_stdout $out => sub {
				no warnings 'redefine';
				local *_close = sub { 1 };
				return eval { App::MtAws::CheckLocalHashCommand::run($options, $j); 1 };
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
				$j->expects("read_journal")->with(should_exist => 1)->returns_ordered->once;
				my $file1 = {size => 123, treehash => 'zz123', mtime => 456};
				$j->{journal_h} = { file1 => $file1 };

				expect_file_exists;
				expect_file_size $file1->{size};
				expect_file_mtime $file1->{mtime};
				expect_open_file;
				expect_treehash $file1->{treehash};

				my ($res, $out) = run_command($options, $j);
				ok $res;
				like $out, qr/^OK file1 $file1->{size} $file1->{treehash}$/m;
				check_ok($out, qw/ok/);
			};
		};
		it "should work when treehash does not match" => sub {
			ordered_test sub {
				$j->expects("read_journal")->with(should_exist => 1)->returns_ordered->once;
				my $file1 = {size => 123, treehash => 'zz123', mtime => 456};
				$j->{journal_h} = { file1 => $file1 };

				expect_file_exists;
				expect_file_size $file1->{size};
				expect_file_mtime $file1->{mtime};
				expect_open_file;
				expect_treehash "not_a_treehash";

				my ($res, $out) = run_command($options, $j);
				ok !$res;
				like $out, qr/^TREEHASH MISSMATCH file1$/m;
				check_ok($out, qw/treehash/);
			};
		};
		it "should work when mtime does not match" => sub {
			ordered_test sub {
				$j->expects("read_journal")->with(should_exist => 1)->returns_ordered->once;
				my $file1 = {size => 123, treehash => 'zz123', mtime => 456};
				$j->{journal_h} = { file1 => $file1 };

				expect_file_exists;
				expect_file_size $file1->{size};
				expect_file_mtime $file1->{mtime}+1;
				expect_open_file;
				expect_treehash $file1->{treehash};

				my ($res, $out) = run_command($options, $j);
				ok $res;
				like $out, qr/^OK file1 $file1->{size} $file1->{treehash}$/m;
				check_ok($out, qw/ok mtime/);
			};
		};
		it "should work when size does not match" => sub {
			ordered_test sub {
				$j->expects("read_journal")->with(should_exist => 1)->returns_ordered->once;
				my $file1 = {size => 123, treehash => 'zz123', mtime => 456};
				$j->{journal_h} = { file1 => $file1 };

				expect_file_exists;
				expect_file_size ($file1->{size}+1);
				expect_file_mtime $file1->{mtime};
				expect_open_file;
				App::MtAws::TreeHash->expects("new")->never;

				my ($res, $out) = run_command($options, $j);
				ok !$res;
				like $out, qr/^SIZE MISSMATCH file1$/m;
				check_ok($out, qw/size/);
			};
		};
		it "should work when size is zero" => sub {
			ordered_test sub {
				$j->expects("read_journal")->with(should_exist => 1)->returns_ordered->once;
				my $file1 = {size => 123, treehash => 'zz123', mtime => 456};
				$j->{journal_h} = { file1 => $file1 };

				expect_file_exists;
				expect_file_size 0;
				App::MtAws::CheckLocalHashCommand->expects("file_mtime")->never;
				App::MtAws::CheckLocalHashCommand->expects("open_file")->never;
				App::MtAws::TreeHash->expects("new")->never;

				my ($res, $out) = run_command($options, $j);
				ok !$res;
				like $out, qr/^ZERO SIZE file1$/m;
				check_ok($out, qw/zero/);
			};
		};
	};
};

runtests unless caller;

1;
