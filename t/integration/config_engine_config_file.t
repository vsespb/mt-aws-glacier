#!/usr/bin/env perl

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
use Test::More tests => 13;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use File::Path;
use TestUtils;
use App::MtAws::Exceptions;
use App::MtAws::Utils;
use POSIX;

warning_fatal();

my $mtroot = get_temp_dir();
my $file = "$mtroot/config_engine_config_file_test.txt";
my $symlink = "$mtroot/config_engine_config_file_test.symlink";

rmtree($file);


my $line = "purge-vault --key=k --secret=s --region=myregion --config=$file --to-vault=myvault --journal x";
SKIP: {
	skip "Cannot run under root", 6 if is_posix_root;
	rmtree($file);
	open F, ">", $file;
	print F " ";
	close F;
	chmod 0000, $file;
	disable_validations sub {
		ok ! defined eval { config_create_and_parse(split(' ', $line)); 1; };
		my $err = get_exception();
		ok $err;
		is $err->{code}, 'cannot_read_config';
		is $err->{config}, hex_dump_string($file);
		is $err->{errno}, get_errno(POSIX::strerror(EACCES));
		is exception_message($err), "Cannot read config file: ".hex_dump_string($file).", errno=".get_errno(POSIX::strerror(EACCES));
	};
}

{
	rmtree($file);
	mkpath($file);
	disable_validations sub {
		ok ! defined eval { config_create_and_parse(split(' ', $line)); 1; };
		my $err = get_exception();
		ok $err;
		is $err->{code}, 'config_file_is_not_a_file';
		is $err->{config}, hex_dump_string($file);
		is exception_message($err), "Config file is not a file: ".hex_dump_string($file);
	}
}

{
	rmtree($file);
	open F, ">", $file;
	close F;
	disable_validations sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $line));
		ok( !$errors && $result, "should work with empty config file");
	}
}

{
	rmtree($file);
	open F, ">", $file;
	print F "dry-run\n";
	close F;
	symlink $file, $symlink or die $!;
	disable_validations sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', "purge-vault --key=k --secret=s --region=myregion --config=$symlink --to-vault=myvault --journal x"));
		ok( !$errors && $result, "should work with symlinked config file");
	}
}

1;
