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
use Test::More tests => 128;
use Test::Deep;
use FindBin;
use POSIX;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJob::MultipartPart;
use App::MtAws::Exceptions;
use TestUtils;

warning_fatal();

use Data::Dumper;


sub create
{
	my ($file, $content) = @_;
	open F, ">", $file;
	print F $content if defined $content;
	close F;

}

my $mtroot = get_temp_dir();
my $relfilename = 'multipart_part';
my $filename = "$mtroot/$relfilename";

sub test_case
{
	my ($partsize, @parts) = @_;
	{
		my @parts_copy = @parts;
		my $last = pop @parts_copy;
		$last = '' unless defined $last;
		ok length($last) <= $partsize;
		is(length($_), $partsize) for @parts_copy;
	}

	create($filename, join('', @parts));
	open my $f, "<", $filename or die;

	my $j = bless { fh => $f, position => 0, partsize => $partsize, th => bless { mock => 'global'}, 'App::MtAws::TreeHash' },
		'App::MtAws::QueueJob::MultipartPart';

	my $expected_start = 0;
	no warnings 'redefine', 'once';

	for my $part_data (@parts) {
		my @data;

		local *App::MtAws::TreeHash::new = sub {
			ok 1;
			bless { mock => 'local'}, 'App::MtAws::TreeHash';
		};
		local *App::MtAws::TreeHash::eat_data = sub {
			my ($th, $dataref) = @_;
			ok $th->{mock};
			push @data, { $th->{mock} => $$dataref };
		};
		local *App::MtAws::TreeHash::calc_tree = sub {
			my ($th) = @_;
			ok $th->{mock};
		};
		local *App::MtAws::TreeHash::get_final_hash = sub {
			my ($th) = @_;
			ok $th->{mock};
			"mockhash $th->{mock}";
		};

		my ($res, $start, $part_final_hash, $attachment) = $j->read_part();

		ok $res;
		is $start, $expected_start;
		is $part_final_hash, 'mockhash local';
		is $$attachment, $part_data;
		cmp_deeply [@data], [ { local => $part_data }, {global => $part_data} ];

		$expected_start += $partsize;
	}


	local *App::MtAws::TreeHash::new = sub { die };
	local *App::MtAws::TreeHash::eat_data = sub { die };
	local *App::MtAws::TreeHash::calc_tree = sub { die };
	local *App::MtAws::TreeHash::get_final_hash = sub { die };

	my @list = $j->read_part();
	is scalar @list, 0;
}

test_case(3, qw/123 456 78/);
test_case(3, qw/123 456 7/);
test_case(3, qw/123 456/);
test_case(1, qw/1 2/);
test_case(2, qw/12/);
test_case(2);


1;
