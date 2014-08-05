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
use Test::More tests => 11;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::ListVaults;
use DeleteTest;
use QueueHelpers;

use Data::Dumper;

{
	my $j = App::MtAws::QueueJob::ListVaults->new();
	cmp_deeply my $res = $j->next,
		App::MtAws::QueueJobResult->full_new(
			task => {
				args => {
					marker => undef,
				},
				action => 'list_vaults',
				cb => test_coderef,
				cb_task_proxy => test_coderef,
			},
			code => JOB_OK,
		);

	expect_wait($j);
	call_callback($res, response => q{{ "VaultList": [ { "x": 42 }] }});
	cmp_deeply $j->{all_vaults}, [ { x => 42 }];
	expect_done($j);
}

{
	my $j = App::MtAws::QueueJob::ListVaults->new();
	my $res = $j->next;
	expect_wait($j);
	call_callback($res, response => q{{ "Marker": "MyMarker", "VaultList": [ { "x": 42 }] }});
	$res = $j->next;
	call_callback($res, response => q{{ "VaultList": [ { "x": 43 }] }});
	expect_done($j);
	cmp_deeply $j->{all_vaults}, [ { x => 42 }, { x => 43 }];
}

1;
