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
use Test::More tests => 18;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::IntermediateFile;
use Carp;
use Fcntl qw/SEEK_SET LOCK_EX SEEK_SET/;



my $rootdir = get_temp_dir();

with_fork
	sub {
		my ($in, $out) = @_;
		my $filename = <$in>;
		chomp $filename;
		my $data_sample = "abcdefz\n";

		ok -f $filename, "file is file";
		ok -r $filename, "file is readable";

		ok open(my $f, ">", $filename), "file opened";
		ok flock($f, LOCK_EX), "file locked";
		ok ((print $f $data_sample), "data written");
		ok (close($f), "file closed");

		ok (open(my $infile, "<", $filename), "file opened for reading");
		my $got_data = do { local $/; <$infile> };
		ok defined($got_data), "we got data";
		ok close($infile), "file closed";

		is $got_data, $data_sample, "file acts well";
		print $out "ok\n";
	},
	sub {
		my ($in, $out) = @_;
		my $I = App::MtAws::IntermediateFile->new(target_file => "$rootdir/somefile");
		print $out $I->tempfilename."\n";
		<$in>;
	};

{
	my $filename;
	with_fork
		sub {
			my ($in, $out) = @_;
			$filename = <$in>;
			chomp $filename;
			ok -f $filename, "file is file";
			print $out "ok\n";
		},
		sub {
			my ($in, $out) = @_;
			my $I = App::MtAws::IntermediateFile->new(target_file => "$rootdir/somefile2");
			print $out $I->tempfilename."\n";
			<$in>;
			print "# exiting from child\n";
			exit 1;
		};
	ok ! -e $filename, "temporary file discarded when child dies";
}

{
	my $filename;
	with_fork
		sub {
			my ($in, $out) = @_;
			$filename = <$in>;
			chomp $filename;
			ok -f $filename, "file is file";
			print $out "ok\n";
		},
		sub {
			my ($in, $out) = @_;
			my $I = App::MtAws::IntermediateFile->new(target_file => "$rootdir/somefile3");
			print $out $I->tempfilename."\n";
			<$in>;
			exit(0);
		};
	ok ! -e $filename, "temporary file discarded when child exits";
}


{
	my $filename;
	{
		my $I = App::MtAws::IntermediateFile->new(target_file => "$rootdir/somefile4");
		$filename = $I->tempfilename;
		with_fork
			sub {
				my ($in, $out) = @_;
				ok -e $filename, "file is file";
				print $out "ok\n";
			},
			sub {
				my ($in, $out) = @_;
				<$in>;
				exit(0);
			};
		ok -e $filename, "file is still exists after child existed";
	}
	ok !-e $filename, "file is discarded";
}

ok 1, "test flow finished";

1;
