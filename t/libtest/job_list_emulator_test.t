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
use Test::More tests => 14;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils;
use JobListEmulator;
use Test::Deep;

warning_fatal();


sub add_page_fixture
{
	my ($E, $id) = @_;
	$E->add_page(
		map {
			{
				Action => 'InventoryRetrieval',
				Completed => JSON_XS_TRUE,
				CompletionDate => 'somedate$_',
				CreationDate => 'somedate$_',
				StatusCode => 'Succeeded',
				JobId => "j$_"
			},
		} (1..10)
	);
}

{
	my $E = JobListEmulator->new();
	add_page_fixture($E, 1);
	like $E->fetch_page, qr/Marker.*null/;
	like $E->fetch_page, qr/Marker.*null/;
}

{
	my $E = JobListEmulator->new();
	add_page_fixture($E, 1);
	add_page_fixture($E, 2);
	like $E->fetch_page, qr/Marker.*marker_1/;
	like $E->fetch_page, qr/Marker.*marker_1/;
}

{
	my $E = JobListEmulator->new();
	add_page_fixture($E, 1);
	add_page_fixture($E, 2);
	like $E->fetch_page, qr/Marker.*marker_1/;
	like $E->fetch_page("marker_1"), qr/Marker.*null/;
}

{
	my $E = JobListEmulator->new();
	add_page_fixture($E, 1);
	add_page_fixture($E, 2);
	add_page_fixture($E, 3);
	like $E->fetch_page, qr/Marker.*marker_1/;
	like $E->fetch_page("marker_1"), qr/Marker.*marker_2/;
	like $E->fetch_page, qr/Marker.*marker_1/;
	like $E->fetch_page("marker_1"), qr/Marker.*marker_2/;
	like $E->fetch_page("marker_2"), qr/Marker.*null/;
	like $E->fetch_page("marker_1"), qr/Marker.*marker_2/;
	like $E->fetch_page, qr/Marker.*marker_1/;
	ok !eval { $E->fetch_page("notamarker"); 1; };
}

1;
