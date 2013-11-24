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
use Test::More tests => 29;
use Test::Deep;
use Carp;
use FindBin;
use JSON::XS;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::Glacier::ListJobs;

use TestUtils;

warning_fatal();

use Data::Dumper;

#
# Unit testing
#

sub create_json
{
	JSON::XS->new()->encode({JobList => [ {
		Action => 'InventoryRetrieval',
		ArchiveId => "somearchiveid",
		ArchiveSHA256TreeHash => "sometreehash",
		Completed => JSON_XS_TRUE,
		CompletionDate => "2013-11-01T22:57:23.968Z",
		CreationDate => "2013-11-01T19:01:19.997Z",
		InventorySizeInBytes => 45012,
		JobDescription => undef,
		JobId => "MyJobId",
		RetrievalByteRange => undef,
		SHA256TreeHash => undef,
		SNSTopic => undef,
		StatusCode => 'Succeeded',
		StatusMessage => 'Succeeded',
		VaultARN => "arn:aws:glacier:eu-west-1:112345678901:vaults/xyz",
		@_
	} ], Marker => "MyMarker"});
}

sub get_list_jobs
{
	App::MtAws::Glacier::ListJobs->new(create_json(@_));
}

{
	my ($marker, $first);
	
	($marker, $first) = get_list_jobs()->get_inventory_entries;
	is $first->{JobId}, "MyJobId", "inventory_entries should work";
	is ref($first->{Completed}), '';

	($marker, $first) = get_list_jobs(Completed => JSON_XS_FALSE)->get_inventory_entries;
	ok !defined $first, "inventory_entries should not work with Completed=false";

	($marker, $first) = get_list_jobs(StatusCode => "SomeStatus")->get_inventory_entries;
	ok !defined $first, "inventory_entries should not work with StatusCode not Succeeded";

	($marker, $first) = get_list_jobs(StatusMessage => "somemessage")->get_inventory_entries;
	is $first->{JobId}, "MyJobId", "inventory_entries should work with different StatusMessage";
}

{
	my ($marker, $first);
	
	($marker, $first) = get_list_jobs(Action => 'ArchiveRetrieval')->get_archive_entries;
	is $first->{JobId}, "MyJobId", "archive_entries should work";
	is ref($first->{Completed}), '';

	($marker, $first) = get_list_jobs(Action => 'ArchiveRetrieval', Completed => JSON_XS_FALSE)->get_archive_entries;
	ok !defined $first, "archive_entries should not work with Completed=false";

	($marker, $first) = get_list_jobs(Action => 'ArchiveRetrieval', StatusCode => "SomeStatus")->get_archive_entries;
	ok !defined $first, "archive_entries should not work with StatusCode not Succeeded";

	($marker, $first) = get_list_jobs(Action => 'ArchiveRetrieval', StatusMessage => "somemessage")->get_archive_entries;
	is $first->{JobId}, "MyJobId", "archive_entries should work with different StatusMessage";
}

#
# testing JSON parsing with real Amazon data
#

{
	my $sample1 = <<'END';
	{"JobList":[
	{"Action":"InventoryRetrieval","ArchiveId":null,"ArchiveSHA256TreeHash":null,"ArchiveSizeInBytes":null,"Completed":true,
	"CompletionDate":"2013-11-01T22:57:23.968Z",
	"CreationDate":"2013-11-01T19:01:19.997Z","InventorySizeInBytes":45012,"JobDescription":null,"JobId":
	"nx-OpZomma5IAaZTlW4L6pYufG6gLhqRrSC1WN-VJFJyr3qKasY8gduswiIOzGQjfrvYiI8o7NvWmghBaMi-Mh3n_xzq",
	"RetrievalByteRange":null,"SHA256TreeHash":null,"SNSTopic":null,"StatusCode":"Succeeded","StatusMessage":"Succeeded",
	"VaultARN":"arn:aws:glacier:eu-west-1:112345678901:vaults/xyz"}],"Marker":null}
END
	
	my ($marker, $first, @others) = App::MtAws::Glacier::ListJobs->new($sample1)->get_inventory_entries();
	
	ok ! defined $marker;
	ok ! @others;
	
	ok ! defined $first->{RetrievalByteRange};
	ok ! defined $first->{JobDescription};
	ok ! defined $first->{ArchiveSHA256TreeHash};
	ok ! defined $first->{ArchiveSizeInBytes};
	ok ! defined $first->{ArchiveId};
	ok ! defined $first->{SHA256TreeHash};
	ok ! defined $first->{SNSTopic};
	is $first->{InventorySizeInBytes}, 45012;
	is $first->{CompletionDate}, '2013-11-01T22:57:23.968Z';
	is $first->{CreationDate}, '2013-11-01T19:01:19.997Z';
	ok $first->{Completed};
	is ref($first->{Completed}), ''; # test that it's not overloaded boolean obj
	ok !!$first->{Completed};
	is $first->{JobId}, 'nx-OpZomma5IAaZTlW4L6pYufG6gLhqRrSC1WN-VJFJyr3qKasY8gduswiIOzGQjfrvYiI8o7NvWmghBaMi-Mh3n_xzq';
	is $first->{VaultARN}, 'arn:aws:glacier:eu-west-1:112345678901:vaults/xyz';
	
}


# testing that booleans work
{
	my $sample1 = <<'END';
	{"JobList":[
	{"Action":"InventoryRetrieval","ArchiveId":null,"ArchiveSHA256TreeHash":null,"ArchiveSizeInBytes":null,"Completed":false,
	"CompletionDate":"2013-11-01T22:57:23.968Z",
	"CreationDate":"2013-11-01T19:01:19.997Z","InventorySizeInBytes":45012,"JobDescription":null,"JobId":
	"nx-OpZomma5IAaZTlW4L6pYufG6gLhqRrSC1WN-VJFJyr3qKasY8gduswiIOzGQjfrvYiI8o7NvWmghBaMi-Mh3n_xzq",
	"RetrievalByteRange":null,"SHA256TreeHash":null,"SNSTopic":null,"StatusCode":"Succeeded","StatusMessage":"Succeeded",
	"VaultARN":"arn:aws:glacier:eu-west-1:112345678901:vaults/xyz"}],"Marker":null}
END
	
	my ($marker, @others) = App::MtAws::Glacier::ListJobs->new($sample1)->get_inventory_entries();
	
	ok ! @others;
}

# testing that marker works
{
	my $sample1 = <<'END';
	{"JobList":[
	{"Action":"InventoryRetrieval","ArchiveId":null,"ArchiveSHA256TreeHash":null,"ArchiveSizeInBytes":null,"Completed":true,
	"CompletionDate":"2013-11-01T22:57:23.968Z",
	"CreationDate":"2013-11-01T19:01:19.997Z","InventorySizeInBytes":45012,"JobDescription":null,"JobId":
	"nx-OpZomma5IAaZTlW4L6pYufG6gLhqRrSC1WN-VJFJyr3qKasY8gduswiIOzGQjfrvYiI8o7NvWmghBaMi-Mh3n_xzq",
	"RetrievalByteRange":null,"SHA256TreeHash":null,"SNSTopic":null,"StatusCode":"Succeeded","StatusMessage":"Succeeded",
	"VaultARN":"arn:aws:glacier:eu-west-1:112345678901:vaults/xyz"}],"Marker":"somemarker"}
END
	
	my ($marker, $first, @others) = App::MtAws::Glacier::ListJobs->new($sample1)->get_inventory_entries();
	
	is $marker, "somemarker";
}
1;

__END__
