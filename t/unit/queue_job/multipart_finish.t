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
use Test::More tests => 42;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartFinish;
use App::MtAws::TreeHash;
use QueueHelpers;
use TestUtils;

warning_fatal();

use Data::Dumper;

# test args validation
{
	my %opts = (
		relfilename => 'somefile',
		mtime => 456,
		upload_id => 'abc',
		filesize => 123,
		th => { mock=> 1 }
	);

	ok eval { my $j = App::MtAws::QueueJob::MultipartFinish->new(%opts); 1 };

	for my $exclude_opt (sort keys %opts) {
		ok exists $opts{$exclude_opt};
		ok ! eval { App::MtAws::QueueJob::MultipartFinish->new( map { $_ => $opts{$_} } grep { $_ ne $exclude_opt } keys %opts ); 1; },
			"should not work without $exclude_opt";
	}

	for my $non_zero_opt (qw/filesize upload_id th/) {
		ok exists $opts{$non_zero_opt};
		ok ! eval { App::MtAws::QueueJob::MultipartFinish->new(%opts, $non_zero_opt => 0); 1; },
	}

	for my $zero_opt (qw/relfilename mtime/) {
		ok exists $opts{$zero_opt};
		local $opts{$zero_opt} = 0;
		ok eval { App::MtAws::QueueJob::MultipartFinish->new( %opts ); 1; }, "should work with $zero_opt=0";
	}
}


sub test_case
{
	my ($relfilename, $mtime) = @_;
	my $th = bless { mock => "mytreehash" }, 'App::MtAws::TreeHash';
	my $j = App::MtAws::QueueJob::MultipartFinish->new(relfilename => $relfilename, upload_id => "someid", filesize => 123, mtime => $mtime, th => $th );

	no warnings 'redefine';

	local *App::MtAws::TreeHash::calc_tree = sub { shift->{tree} = "my_final_hash" };
	local *App::MtAws::TreeHash::get_final_hash = sub { shift->{tree} };

	cmp_deeply my $res = $j->next,
		App::MtAws::QueueJobResult->full_new(code => JOB_OK,
		task => { args => {relfilename => $relfilename, upload_id => "someid", filesize => 123, mtime => $mtime, final_hash => "my_final_hash" },
		action => 'finish_upload', cb => test_coderef, cb_task_proxy => test_coderef});
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
	expect_wait($j);
	call_callback($res);
	expect_done($j);
}

test_case "somefile", 123456;
test_case "0", 123456;
test_case "somefile2", 0;

1;
