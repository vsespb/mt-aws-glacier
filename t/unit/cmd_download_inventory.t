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
use utf8;
use Test::More tests => 8;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::Journal;
use File::Path;
use POSIX;
use TestUtils;
use POSIX;
use Time::Local;
use Carp;
use App::MtAws::Utils;
use App::MtAws::MetaData;
use App::MtAws::Command::DownloadInventory;

warning_fatal();

my $mtroot = get_temp_dir();
my $localroot = "$mtroot/download_inventory";
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


my $now = time();
{
	# 3rd party archive
	assert_entry(
	{
		ArchiveId => $data->{archive_id},
		ArchiveDescription => 'mtglacier archive',
		CreationDate => strftime("%Y%m%dT%H%M%SZ", gmtime($now)),
		Size => $data->{size},
		SHA256TreeHash => $data->{treehash},
	},
	{
		time => $now,
		type => 'CREATED',
		treehash => $data->{treehash},
		mtime => undef,
		archive_id => $data->{archive_id},
		relfilename => $data->{archive_id},
		size => $data->{size},
	}
	);
	# authentic archive
	assert_entry(
	{
		ArchiveId => $data->{archive_id},
		ArchiveDescription => App::MtAws::MetaData::meta_encode($data->{relfilename}, $now - 111),
		CreationDate => strftime("%Y%m%dT%H%M%SZ", gmtime($now)),
		Size => $data->{size},
		SHA256TreeHash => $data->{treehash},
	},
	{
		time => $now,
		type => 'CREATED',
		treehash => $data->{treehash},
		mtime => $now - 111,
		archive_id => $data->{archive_id},
		relfilename => $data->{relfilename},
		size => $data->{size},
	}
	);
}

sub assert_entry
{
	assert_entry_json(@_);
	assert_entry_csv(@_);
}

sub assert_entry_json
{
	my ($inp, $out) = @_;
	unlink $journal;
	my $jdata = {
		"VaultARN" => "arn:aws:glacier:us-east-1:123456:vaults/test",
		"InventoryDate" => strftime("%Y%m%dT%H%M%SZ", gmtime(time)),
		"ArchiveList" => [$inp],
	};
	my $json = JSON::XS->new->allow_nonref->ascii->pretty->encode($jdata);
	my $J = App::MtAws::Journal->new(journal_file=> $journal, root_dir => $rootdir);
	no warnings 'redefine';
	local *App::MtAws::Journal::add_entry = sub {
		my (undef, $e) = @_;
		ok cmp_deeply $e, $out;
	};
	App::MtAws::Command::DownloadInventory::parse_and_write_journal($J, INVENTORY_TYPE_JSON, \$json);
}

sub assert_entry_csv
{
	my ($inp, $out) = @_;
	unlink $journal;
	my $jdata = {
		"VaultARN" => "arn:aws:glacier:us-east-1:123456:vaults/test",
		"InventoryDate" => strftime("%Y%m%dT%H%M%SZ", gmtime(time)),
		"ArchiveList" => [$inp],
	};
	my $csv = <<"END";
ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash
$inp->{ArchiveId},"$inp->{ArchiveDescription}",$inp->{CreationDate},$inp->{Size},$inp->{SHA256TreeHash}
END
	my $J = App::MtAws::Journal->new(journal_file=> $journal, root_dir => $rootdir);
	no warnings 'redefine';
	local *App::MtAws::Journal::add_entry = sub {
		my (undef, $e) = @_;
		ok cmp_deeply $e, $out;
	};
	App::MtAws::Command::DownloadInventory::parse_and_write_journal($J, INVENTORY_TYPE_CSV, \$csv);
}

unlink $journal;
1;
