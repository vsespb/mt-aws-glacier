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
use Test::More tests => 13;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadInventory;
use DeleteTest;
use QueueHelpers;
use TestUtils;

warning_fatal();

use Data::Dumper;

# test args validation
{
	ok eval { App::MtAws::QueueJob::DownloadInventory->new(job_id=> 'somejob'); 1; };
	ok !eval { App::MtAws::QueueJob::DownloadInventory->new(xname => 1); 1; };
}

my $j = App::MtAws::QueueJob::DownloadInventory->new(job_id => 'somejob');
cmp_deeply my $res = $j->next,
	App::MtAws::QueueJobResult->full_new(
		task => {
			args => {
				job_id => 'somejob',
			},
			action => 'inventory_download_job',
			cb => test_coderef,
			cb_task_proxy => test_coderef,
		},
		code => JOB_OK,
	);

expect_wait($j);
my $data = "123";
call_callback_with_attachment($res, { inventory_type => "MyInventoryType" }, \$data);
is $j->{inventory_raw_ref}, \$data;
is $j->{inventory_type}, "MyInventoryType";
expect_done($j);

{
	my $j = App::MtAws::QueueJob::DownloadInventory->new(job_id => 'somejob');
	$j->next;
	expect_wait($j);
	ok ! eval { call_callback_with_attachment($res, {}); 1 }, "should confess without attachment";
	ok $@ =~ /no attachment/;

}

1;
