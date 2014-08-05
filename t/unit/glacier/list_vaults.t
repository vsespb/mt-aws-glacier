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
use Carp;
use FindBin;
use JSON::XS;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::Glacier::ListVaults;



use Data::Dumper;

#
# Unit testing
#

sub create_json
{
	JSON::XS->new()->encode({VaultList => [ {
		CreationDate => "2013-11-01T19:01:19.997Z",
		LastInventoryDate => "2013-10-01T19:01:19.997Z",
		NumberOfArchives => 100,
		SizeInBytes => 100_500,
		VaultARN => "arn:aws:glacier:eu-west-1:112345678901:vaults/xyz",
		VaultName => "myvault",
		@_
	}, {
		CreationDate => "2013-10-01T19:01:19.997Z",
		LastInventoryDate => "2013-09-01T19:01:19.997Z",
		NumberOfArchives => 200,
		SizeInBytes => 200_500,
		VaultARN => "arn:aws:glacier:eu-west-1:112345678901:vaults/def",
		VaultName => "myvault2",
		@_
	} ], Marker => "MyMarker"});
}

sub get_list_vaults
{
	App::MtAws::Glacier::ListVaults->new(create_json(@_));
}

{
	my ($marker, $first, $second);

	($marker, $first, $second) = get_list_vaults()->get_list_vaults;
	is $marker, 'MyMarker';
	is $first->{CreationDate}, "2013-11-01T19:01:19.997Z";
	is $first->{LastInventoryDate}, "2013-10-01T19:01:19.997Z";
	is $first->{NumberOfArchives}, 100;
	is $first->{SizeInBytes}, 100500;
	is $first->{VaultARN}, "arn:aws:glacier:eu-west-1:112345678901:vaults/xyz";
	is $first->{VaultName}, "myvault";

	is $second->{CreationDate}, "2013-10-01T19:01:19.997Z";
	is $second->{LastInventoryDate}, "2013-09-01T19:01:19.997Z";
	is $second->{NumberOfArchives}, 200;
	is $second->{SizeInBytes}, 200500;
	is $second->{VaultARN}, "arn:aws:glacier:eu-west-1:112345678901:vaults/def";
	is $second->{VaultName}, "myvault2";
}


__END__
