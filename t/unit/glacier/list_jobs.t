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
use Test::More tests => 53;
use Test::Deep;
use Carp;
use FindBin;
use JSON::XS;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::Glacier::ListJobs;




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

# TODO: test with real Amazon data for archive retrievals

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

#
##
## 31-Dec-2013 Amazon extended API with range inventory retrieval. This could affect listjobs
##
#

# real data, where none of InventoryRetrievalParameters defined

{
	my $sample1 = <<'END';
{"JobList":[{"Action":"InventoryRetrieval","ArchiveId":null,"ArchiveSHA256TreeHash":null,"ArchiveSizeInBytes":null,
"Completed":true,"CompletionDate":"2014-01-03T04:05:29.864Z","CreationDate":"2014-01-03T00:13:24.350Z",
"InventoryRetrievalParameters":{"EndDate":null,"Format":"JSON","Limit":null,"Marker":null,"StartDate":null},
"InventorySizeInBytes":8128817,"JobDescription":null,"JobId":"Y88K008l_-X-o7bHFU6U8aKusnfPiqAUuUGu9Yl25J9ugwA86Du5BOf0Ce61GTGrcE6zcr5pIougjPomV-d2HeRmixKx","RetrievalByteRange":null,
"SHA256TreeHash":null,"SNSTopic":null,"StatusCode":"Succeeded","StatusMessage":"Succeeded",
"VaultARN":"arn:aws:glacier:us-east-1:111111111111:vaults/test1"}],"Marker":null}
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
	is $first->{InventorySizeInBytes}, 8128817;
	is $first->{CompletionDate}, '2014-01-03T04:05:29.864Z';
	is $first->{CreationDate}, '2014-01-03T00:13:24.350Z';
	ok $first->{Completed};
	is ref($first->{Completed}), ''; # test that it's not overloaded boolean obj
	ok !!$first->{Completed};
	is $first->{JobId}, 'Y88K008l_-X-o7bHFU6U8aKusnfPiqAUuUGu9Yl25J9ugwA86Du5BOf0Ce61GTGrcE6zcr5pIougjPomV-d2HeRmixKx';
	is $first->{VaultARN}, 'arn:aws:glacier:us-east-1:111111111111:vaults/test1';

}

# real data, where most of InventoryRetrievalParameters keys defined

{
	my $sample1 = <<'END';
{"JobList":[{"Action":"InventoryRetrieval","ArchiveId":null,"ArchiveSHA256TreeHash":null,"ArchiveSizeInBytes":null,
"Completed":true,"CompletionDate":"2014-01-03T04:05:29.864Z","CreationDate":"2014-01-03T00:13:24.350Z",
"InventoryRetrievalParameters":{"EndDate":"2013-03-20T17:03:43Z","Format":"JSON","Limit":"100","Marker":null,"StartDate":"2012-03-20T17:03:43Z"},
"InventorySizeInBytes":8128817,"JobDescription":null,"JobId":"Y88K008l_-X-o7bHFU6U8aKusnfPiqAUuUGu9Yl25J9ugwA86Du5BOf0Ce61GTGrcE6zcr5pIougjPomV-d2HeRmixKx","RetrievalByteRange":null,
"SHA256TreeHash":null,"SNSTopic":null,"StatusCode":"Succeeded","StatusMessage":"Succeeded",
"VaultARN":"arn:aws:glacier:us-east-1:111111111111:vaults/test1"}],"Marker":null}
END

	my ($marker, $first, @others) = App::MtAws::Glacier::ListJobs->new($sample1)->get_inventory_entries();
	ok ! defined $first, "should not work when InventoryRetrievalParameters defined";
}

# mixing real data and autogenerated, one key at a time in InventoryRetrievalParameters defined

{
	my %data = (
		EndDate => q{"2013-03-20T17:03:43Z"},
		Limit => q{100},
		Marker => q{"ZZZZZZZZZZZ-o7bHFU6U8aKusnfPiqAUuUGu9Yl25J9ugwA86Du5BOf0Ce61GTGrcE6zcr5pIougjPomV-d2HeRmixKx"},
		StartDate => q{"2012-03-20T17:03:43Z"},
	);

	for my $key ("NONE", keys %data) {
		my %d = %data;
		$d{$_} = "null" for (grep { $_ ne $key }keys %data);
		my $sample1 = <<"END";
{"JobList":[{"Action":"InventoryRetrieval","ArchiveId":null,"ArchiveSHA256TreeHash":null,"ArchiveSizeInBytes":null,
"Completed":true,"CompletionDate":"2014-01-03T04:05:29.864Z","CreationDate":"2014-01-03T00:13:24.350Z",
"InventoryRetrievalParameters":{"EndDate":$d{EndDate},"Format":"JSON","Limit":$d{Limit},"Marker":$d{Marker},"StartDate":$d{StartDate}},
"InventorySizeInBytes":8128817,"JobDescription":null,"JobId":"Y88K008l_-X-o7bHFU6U8aKusnfPiqAUuUGu9Yl25J9ugwA86Du5BOf0Ce61GTGrcE6zcr5pIougjPomV-d2HeRmixKx","RetrievalByteRange":null,
"SHA256TreeHash":null,"SNSTopic":null,"StatusCode":"Succeeded","StatusMessage":"Succeeded",
"VaultARN":"arn:aws:glacier:us-east-1:111111111111:vaults/test1"}],"Marker":null}
END
	# next line aligned to satisfy Test::Tabs
	my ($marker, $first, @others) = App::MtAws::Glacier::ListJobs->new($sample1)->get_inventory_entries();
		if ($key eq "NONE") {
			is $first->{JobId}, 'Y88K008l_-X-o7bHFU6U8aKusnfPiqAUuUGu9Yl25J9ugwA86Du5BOf0Ce61GTGrcE6zcr5pIougjPomV-d2HeRmixKx';
		} else {
			ok ! defined $first, "should not work when InventoryRetrievalParameters defined";
		}
	}
}

# testing no autovivification in _full_inventory
{
	my $x = { a => 42 };
	App::MtAws::Glacier::ListJobs::_full_inventory for $x;
	ok !exists $x->{InventoryRetrievalParameters};
}

1;

__END__

example of real data with right job description
"InventorySizeInBytes":null,"JobDescription":"mtijob1 eyJ0eXBlIjoiZnVsbCJ9","JobId":"IV7wu2Oc

