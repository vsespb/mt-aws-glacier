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
use Test::More tests => 376;
use Test::Deep;
use Carp;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::FetchAndDownloadInventory;
use DeleteTest;
use QueueHelpers;
use JobListEmulator;
use TestUtils;

warning_fatal();

use Data::Dumper;

sub expect_job_id
{
	my ($E, $expected_job_id) = @_;
	my $j = App::MtAws::QueueJob::FetchAndDownloadInventory->new();

	my $is_ok = 0;
	my $job_id = undef;
	my $ourdata = \"ourdata";
	my $i = 0;
	while() {
		confess if $i++ > 1000; # protection

		my $res = $j->next;
		if ($res->{code} eq JOB_OK) {
			if ($res->{task}{action} eq 'inventory_fetch_job') {
				my $page = $E->fetch_page($res->{task}{args}{marker});
				expect_wait($j);
				call_callback($res, response => $page);
			} elsif ($res->{task}{action} eq 'inventory_download_job') {
				$job_id = $res->{task}{args}{job_id};
				expect_wait($j);
				call_callback_with_attachment($res, { inventory_type => "MyType" }, $ourdata);
				expect_done($j);
				$is_ok = 1;
				last;
			}
		} elsif ($res->{code} eq JOB_DONE) {
			ok !defined $j->{inventory_raw_ref};
			$is_ok = 1;
			last;
		} else {
			confess;
		}
	}
	ok $is_ok;
	is $job_id, $expected_job_id;
	if (defined $expected_job_id) {
		is $j->{inventory_raw_ref}, $ourdata;
		is $j->{inventory_type}, "MyType";
	} else {
		ok exists $j->{inventory_raw_ref};
		ok exists $j->{inventory_type};
		ok !defined $j->{inventory_raw_ref};
		ok !defined $j->{inventory_type};
	}

}

# that pretty complex test was invented when old FetchAndDownloadInventory implementation was alive
# (example in revision 87eff2b3290008448b2a2eb352964666a91a6ac8 )
# it's possible that some tested cases look now unneede

for my $before_archives (0, 1, 2, 3) {
	for my $after_archives (0, 1, 2, 3) {
		my $E = JobListEmulator->new();
		$E->add_archive_fixture($_) for (1..$before_archives);
		$E->add_inventory_fixture(1000);
		$E->add_archive_fixture(2000+$_) for (1..$after_archives);
		expect_job_id($E, "j_1000_1");
	}
}

for my $before_archives (0, 1, 2, 3) {
	my $E = JobListEmulator->new();
	$E->add_archive_fixture($_) for (1..$before_archives);
	expect_job_id($E, undef);
}

{
	my $E = JobListEmulator->new();
	$E->add_inventory_with_date(1000, "2013-11-01T19:01:19.997Z");
	$E->add_inventory_with_date(2000, "2013-11-02T19:01:19.997Z");
	expect_job_id($E, "j_2000_1");
}

{
	my $E = JobListEmulator->new();
	$E->add_inventory_with_date(2000, "2013-11-01T19:01:19.997Z");
	$E->add_inventory_with_date(1000, "2013-11-02T19:01:19.997Z");
	expect_job_id($E, "j_1000_1");
}

{
	my $E = JobListEmulator->new();
	$E->add_inventory_with_date(1000, "2013-11-02T19:01:19.997Z");
	$E->add_inventory_with_date(2000, "2013-11-01T19:01:19.997Z");
	expect_job_id($E, "j_1000_1");
}

{
	my $E = JobListEmulator->new();
	$E->add_inventory_with_date(1000, "2013-11-02T19:01:19.997Z");
	$E->add_inventory_with_date(2000, "2013-11-03T19:01:19.997Z");
	$E->add_inventory_with_date(3000, "2013-11-01T19:01:19.997Z");
	expect_job_id($E, "j_2000_1");
}

{
	my $E = JobListEmulator->new();
	$E->add_inventory_with_date(1000, "2013-11-04T19:01:19.997Z");
	$E->add_inventory_with_date(2000, "2013-11-03T19:01:19.997Z");
	$E->add_inventory_with_date(3000, "2013-11-01T19:01:19.997Z");
	expect_job_id($E, "j_1000_1");
}

{
	my $E = JobListEmulator->new();
	$E->add_inventory_with_date(1000, "2013-11-04T19:01:19.997Z");
	$E->add_inventory_with_date(2000, "2013-11-03T19:01:19.997Z");
	$E->add_inventory_with_date(3000, "2013-11-05T19:01:19.997Z");
	expect_job_id($E, "j_3000_1");
}

1;

__END__
