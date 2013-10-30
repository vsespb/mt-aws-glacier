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
use Test::More tests => 5;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::Journal;
use App::MtAws::Exceptions;
use File::Path;
use POSIX;
use TestUtils;

warning_fatal();

my $mtroot = get_temp_dir();
my $localroot = "$mtroot/cmd_check_local_hash";
my $journal = "$localroot/journal";
my $rootdir = "$localroot/root";
mkpath($localroot);
mkpath($rootdir);

my $data = {
	archive_id => "HdGDbije6lWPT8Q8S3uOWJF6Ou9MWRlrfMGDr6TCrhXuDqJ1pzwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	job_id => "HdGDbije6lWPT8Q8S3uOWJF6777MWRlrfMGDr688888888888zwKR6XV4l1IZ-VrDd2rlLxDFACqnuJouYTzsT5zd6s2ZEAHfRQFriVbjpFfJ1uWruHRRXIrFIma4PVuz-fp9_pBkA",
	size => 7684356,
	'time' => 1355666755,
	mtime => 1355566755,
	relfilename => 'def/abc',
	treehash => '1368761bd826f76cae8b8a74b3aae210b476333484c2d612d061d52e36af631a',
};

my $content = "hello\n";

{
	unlink $journal;
	my $J = App::MtAws::Journal->new(journal_file=> $journal, root_dir => $rootdir);
	$J->open_for_write();
	$J->add_entry({ type=> 'CREATED', time => $data->{time}, mtime => $data->{mtime}, archive_id => $data->{archive_id},
		size => length($content), treehash => $data->{treehash}, relfilename => $data->{relfilename} });
}

SKIP: {
	skip "Cannot run under root", 5 if is_posix_root;
	my $file = "$rootdir/def/abc";
	mkpath "$rootdir/def";
	chmod 0744, $file;
	open F, '>', $file or die $!;
	print F $content;
	close F;
	chmod 0000, $file;

	my $options = {
		region => 'reg',
		journal => $journal,
		dir => $rootdir,
		journal_encoding => 'UTF-8',
	};

	my $j = App::MtAws::Journal->new(journal_encoding => $options->{'journal-encoding'},
		journal_file => $options->{journal},
		root_dir => $options->{dir},
		filter => $options->{filters}{parsed});
	require App::MtAws::Command::CheckLocalHash;

	my $out='';
	ok ! defined capture_stdout $out, sub {
		eval {
			App::MtAws::Command::CheckLocalHash::run($options, $j);
			1;
		};
	};
	my $err = $@;

	cmp_deeply $err, superhashof { code => 'check_local_hash_errors',
		message => "check-local-hash reported errors"};

	ok $out =~ m!CANNOT OPEN file def/abc!;
	ok $out =~ m!1 ERRORS!;
	ok index($out, get_errno(strerror(EACCES))) != -1;
	# TODO: check also that 'next' is called!

	chmod 0744, $file;
	unlink $file;
1;

}


1;
