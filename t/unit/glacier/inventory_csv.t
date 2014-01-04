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
use Test::More tests => 155;
use Test::Deep;
use Carp;
use FindBin;
use Scalar::Util qw/weaken/;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::Glacier::Inventory::CSV;

use TestUtils;

warning_fatal();

use Data::Dumper;

sub test_full_file
{
	my $data = App::MtAws::Glacier::Inventory::CSV->new(shift)->get_archives();
	cmp_deeply $data, shift;
}

test_full_file <<'END',
ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash
a,b,c,d,e
END
[
	{ArchiveId => 'a', ArchiveDescription=>'b', CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'}
];

test_full_file "ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash\015\012a,b,c,d,e",
[
	{ArchiveId => 'a', ArchiveDescription=>'b', CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'}
];

test_full_file "ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash\015\012a,b,c,d,e\015\012",
[
	{ArchiveId => 'a', ArchiveDescription=>'b', CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'}
];

test_full_file "ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash\015\012a,b,c,d,e\012",
[
	{ArchiveId => 'a', ArchiveDescription=>'b', CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'}
];

test_full_file "ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash\015\012",[];
test_full_file "ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash\012",[];
test_full_file "ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash",[];


ok ! eval { test_full_file "ArchiveId,ArchiveDescription,AnotherField,CreationDate,Size,SHA256TreeHash",[]; 1 };
like "$@", qr/Bad CSV header/i;
ok ! eval { test_full_file "zzz",[]; 1 };
like "$@", qr/Bad CSV header/i;

ok ! eval { test_full_file "ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash\na,b",[]; 1 };
like "$@", qr/Bad CSV line/i;


test_full_file <<'END',
ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash
a,b,c,d,e
x,y,z,1,2
END
[
	{ArchiveId => 'a', ArchiveDescription=>'b', CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'},
	{ArchiveId => 'x', ArchiveDescription=>'y', CreationDate=>'z', Size => '1', SHA256TreeHash => '2'}
];

test_full_file <<'END',
CreationDate,Size,ArchiveId,ArchiveDescription,SHA256TreeHash
a,b,c,d,e
x,y,z,1,2
END
[
	{ArchiveId => 'c', ArchiveDescription=>'d', CreationDate=>'a', Size => 'b', SHA256TreeHash => 'e'},
	{ArchiveId => 'z', ArchiveDescription=>'1', CreationDate=>'x', Size => 'y', SHA256TreeHash => '2'}
];

sub test_line
{
	my ($line, $expected) = @_;
	my $file = "ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash\n$line\n";
	test_full_file($file, [$expected]);
	$file .= "$line\n";
	test_full_file($file, [$expected, $expected]);
}


{
	my @a = qw/a b c d e/;
	for my $f (0..4) {
		my $af = $a[$f];
		local $a[$f] = " $af";
		test_line join(',', @a), {ArchiveId => 'a', ArchiveDescription=>'b', CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'};

		local $a[$f] = "$af ";
		test_line join(',', @a), {ArchiveId => 'a', ArchiveDescription=>'b', CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'};

		local $a[$f] = " $af ";
		test_line join(',', @a), {ArchiveId => 'a', ArchiveDescription=>'b', CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'};
	}
}

sub test_description
{
	my ($field, $expected) = @_;
	test_line "a,$field,c,d,e", {ArchiveId => 'a', ArchiveDescription=>$expected, CreationDate=>'c', Size => 'd', SHA256TreeHash => 'e'};

	my $file = "ArchiveDescription,ArchiveId,CreationDate,Size,SHA256TreeHash\n$field,a,b,c,d\n";
	test_full_file($file, [{ArchiveId => 'a', ArchiveDescription=>$expected, CreationDate=>'b', Size => 'c', SHA256TreeHash => 'd'}]);

	$file = "ArchiveId,CreationDate,Size,SHA256TreeHash,ArchiveDescription\na,b,c,d,$field\n";
	test_full_file($file, [{ArchiveId => 'a', ArchiveDescription=>$expected, CreationDate=>'b', Size => 'c', SHA256TreeHash => 'd'}]);

	$file = "ArchiveId,CreationDate,ArchiveDescription,Size,SHA256TreeHash\na,b,$field,c,d\n";
	test_full_file($file, [{ArchiveId => 'a', ArchiveDescription=>$expected, CreationDate=>'b', Size => 'c', SHA256TreeHash => 'd'}]);
}

# first chunk of real data from Amazon

test_description
	q!"{\"Path\":\"glacier-ui.exe\",\"UTCDateModified\":\"20130313T040002Z\"}"!,
	q!{"Path":"glacier-ui.exe","UTCDateModified":"20130313T040002Z"}!;

test_description
	q!"{\"Path\":\"dir2/+BEQEMAQ5BDs-3\",\"UTCDateModified\":\"20130322T120043Z\"}"!,
	q!{"Path":"dir2/+BEQEMAQ5BDs-3","UTCDateModified":"20130322T120043Z"}!;


test_description
	q!"{\"Path\":\"dir1/file1\",\"UTCDateModified\":\"20130322T120026Z\"}"!,
	q!{"Path":"dir1/file1","UTCDateModified":"20130322T120026Z"}!;

test_description
	q!"{\"Path\":\"dir1/+BEQEMAQ5BDs-2\",\"UTCDateModified\":\"20130322T120033Z\"}"!,
	q!{"Path":"dir1/+BEQEMAQ5BDs-2","UTCDateModified":"20130322T120033Z"}!;

test_description
	q!""!,
	q!!;

test_description
	q!","!,
	q!,!;

test_description
	q!"\\""!,
	q!"!;

test_description
	q!"x\\"x"!,
	q!x"x!;

test_description
	q!"ZZZZZZZZzzzzzzz,\\"\\"\\", ,\\\\""!,
	q!ZZZZZZZZzzzzzzz,""", ,\\"!;

test_description
	q!"\\"!,
	q!\\!;

test_description
	q!"\\\\""!,
	q!\\"!;

# second chunk of real data from Amazon

test_description
	q!"mt2 eyJmaWxlbmFtZSI6ImZpbGUudHh0IiwibXRpbWUiOiIyMDEzMTIxOVQwODMzMDFaIn0"!,
	q!mt2 eyJmaWxlbmFtZSI6ImZpbGUudHh0IiwibXRpbWUiOiIyMDEzMTIxOVQwODMzMDFaIn0!;
test_description
	q!"\\"!,
	q!\\!;
test_description
	q!"\\\\""!,
	q!\\"!;
test_description
	q!"\\""!,
	q!"!;
test_description
	q!"a\\b"!,
	q!a\\b!;
test_description
	q!"\\\\"\\"!,
	q!\\"\\!;
test_description
	q!"\\\\"!,
	q!\\\\!;
test_description
	q!","!,
	q!,!;
test_description
	q!"\\\\"\\\\"\\\\\\"\\"!,
	q!\\"\\"\\\\"\\!;
test_description
	q!"\\x"!,
	q!\\x!;
test_description
	q!"x\\"!,
	q!x\\!;

__END__
