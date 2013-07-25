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
use Test::More tests => 15;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use TestUtils;
use App::MtAws::IntermediateFile;
use File::Temp;
use Carp;
use Fcntl qw/SEEK_SET LOCK_EX LOCK_UN SEEK_SET/;

warning_fatal();

my $TEMP = File::Temp->newdir();
my $rootdir = $TEMP->dirname();

with_fork
	sub {
		my (undef, $fromchild) = @_;
		my $filename = <$fromchild>;
		chomp $filename;
		my $data_sample = "abcdefz\n";

		ok -f $filename, "file is file";
		ok -r $filename, "file is readable";

		ok open(my $f, ">", $filename), "file opened";
		ok flock($f, LOCK_EX), "file locked";
		ok ((print $f $data_sample), "data written");
		ok (flock($f, LOCK_UN ), "file unlocked");
		ok (close($f), "file closed");

		ok (open(my $in, "<", $filename), "file opened for reading");
		my $got_data = do { local $/; <$in> };
		ok defined($got_data), "we got data";
		ok close($in), "file closed";

		is $got_data, $data_sample, "file acts well";
	},
	sub {
		my ($tochild, $fromchild) = @_;
		my $I = App::MtAws::IntermediateFile->new(dir => $rootdir);
		print $fromchild $I->filename."\n";
		<$tochild>;
	};

{
	my $filename;
	with_fork
		sub {
			my ($tochild, $fromchild) = @_;
			$filename = <$fromchild>;
			chomp $filename;
			my $data_sample = "abcdefz\n";
			ok -f $filename, "file is file";
			print $tochild "ok\n";
		},
		sub {
			my ($tochild, $fromchild) = @_;
			my $I = App::MtAws::IntermediateFile->new(dir => $rootdir);
			print $fromchild $I->filename."\n";
			<$tochild>;
			die "diying from child\n";
		};
	ok ! -e $filename, "temporary file discarded when child dies";
}

{
	my $filename;
	with_fork
		sub {
			my ($tochild, $fromchild) = @_;
			$filename = <$fromchild>;
			chomp $filename;
			my $data_sample = "abcdefz\n";
			ok -f $filename, "file is file";
			print $tochild "ok\n";
		},
		sub {
			my ($tochild, $fromchild) = @_;
			my $I = App::MtAws::IntermediateFile->new(dir => $rootdir);
			print $fromchild $I->filename."\n";
			<$tochild>;
			exit(0);
		};
	ok ! -e $filename, "temporary file discarded when child exits";
}

1;
