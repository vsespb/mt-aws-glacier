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
use Test::More tests => 26;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Retrieve;
use DeleteTest;
use QueueHelpers;



use Data::Dumper;

my %opts = (filename => '/tmp/path/somefile', relfilename => 'somefile', archive_id => 'abc');

# test args validation
{
	ok  eval { App::MtAws::QueueJob::Retrieve->new( map { $_ => $opts{$_} } qw/filename relfilename archive_id/); 1; };

	ok !eval { App::MtAws::QueueJob::Retrieve->new( map { $_ => $opts{$_} } qw/filename archive_id/); 1; };
	ok  eval { App::MtAws::QueueJob::Retrieve->new((map { $_ => $opts{$_} } qw/filename archive_id/), relfilename => 0); 1; };

	ok !eval { App::MtAws::QueueJob::Retrieve->new( map { $_ => $opts{$_} } qw/relfilename archive_id/); 1; };
	ok  eval { App::MtAws::QueueJob::Retrieve->new((map { $_ => $opts{$_} } qw/relfilename archive_id/), filename => 0); 1; };

	ok !eval { App::MtAws::QueueJob::Retrieve->new( map { $_ => $opts{$_} } qw/filename relfilename/); 1; };
}

for my $relfilename ($opts{relfilename}, 0) {
	for my $filename ($opts{filename}, 0) {
		my $j = App::MtAws::QueueJob::Retrieve->new(
			relfilename => $relfilename, filename => $filename, archive_id => $opts{archive_id}
		);
		cmp_deeply my $res = $j->next,
			App::MtAws::QueueJobResult->full_new(
				task => {
					args => {
						filename => $filename,
						relfilename => $relfilename,
						archive_id => $opts{archive_id},
					},
					action => 'retrieve_archive',
					cb => test_coderef,
					cb_task_proxy => test_coderef,
				},
				code => JOB_OK,
			);
		expect_wait($j);
		call_callback($res);
		expect_done($j);
	}
}


1;
