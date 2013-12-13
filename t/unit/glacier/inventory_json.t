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
use Test::More tests => 5;
use Test::Deep;
use Carp;
use FindBin;
use Scalar::Util qw/weaken/;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::Glacier::Inventory::JSON;

use TestUtils;

warning_fatal();

use Data::Dumper;


#
# testing JSON parsing with real Amazon data
#

{
	my $sample1 = <<'END';
{"VaultARN":"arn:aws:glacier:us-east-1:222222223333:vaults/test1","InventoryDate":"2013-11-06T02:51:29Z","ArchiveList":[
{"ArchiveId":"95qYTtf_E_VV9B-bfk6LrbCmM85J7youtfNWepEVEHF1wbp3QD42trmANUCDindSQ6rvg20EmKSHRo6jwmw6CKNoCKeJAPlzl-n7_VVp3GG20QQySwc5MccL5y_0yYeDTDL6XXd3Sw",
"ArchiveDescription":"textst zz123",
"CreationDate":"2012-08-23T19:08:30Z","Size":3000000,"SHA256TreeHash":"ef0d259231262eae49a48b6c379a5577b05db3910361498d571f0c9c46be2513"},
{"ArchiveId":"xtsSbQFG3BHgE9pk9ocSAXvpaNhXY9KwVUJjASW-5V3jzAbCjNzN5WlhQqcvRBsEUUa13OFc_9NIo2TIxCI6sumcdM5QC4wdL_uyhWxTpE8Bt5ODPchNhvnpeliMc0WnW4I01lA4Sw",
"ArchiveDescription":"mt2 textst","CreationDate":"2012-08-23T19:09:17Z","Size":25000000,"SHA256TreeHash":"ef119aacb102f0c8790e0747a49f10e9b5d785656c04da3f069e6d26c7cc5818"},
{"ArchiveId":"OdEuDQOmt37jouhFioL-rleBdtLs4-e20FpQWwjp98XL0Ls5xRP9ghibqY_rrw07M9-_74LXRosXYsWXhPjaohxMeC02oGNA1SJU03rWibdye0BaNFsU8X5GYjGMNwmGDZF0whQxGg",
"ArchiveDescription":"","CreationDate":"2012-08-23T19:11:42Z","Size":25000000,"SHA256TreeHash":"af119aacb102f0c8790e0747a49f10e9b5d785656c04da3f069e6d26c7cc5818"},
{"ArchiveId":"fH4iYmeZsnll5jwiO4aIIlHBEXZ5KjF-77hIz3TzPu3Ewjl1dxfhtEZWT2IteLjFHVhdrF2JctxhtRKsLmwenDuqBKj3iW-LYR1MXqkNJbaB4BTgnhCFoRkCmCA9rr-_Yr3CMJZoew",
"ArchiveDescription":"textstZ","CreationDate":"2012-08-23T19:20:08Z","Size":25000000,"SHA256TreeHash":"ef119aacb102f0c8790e0747a49f10e9b5d785656c04da3f069e6d26c7cc5819"}
]}
END

	my $data = App::MtAws::Glacier::Inventory::JSON->new($sample1)->get_archives();
	cmp_deeply $data, [
		{
			ArchiveId => "95qYTtf_E_VV9B-bfk6LrbCmM85J7youtfNWepEVEHF1wbp3QD42trmANUCDindSQ6rvg20EmKSHRo6jwmw6CKNoCKeJAPlzl-n7_VVp3GG20QQySwc5MccL5y_0yYeDTDL6XXd3Sw",
			ArchiveDescription => "textst zz123",
			CreationDate => "2012-08-23T19:08:30Z",
			Size => 3000000,
			SHA256TreeHash => 'ef0d259231262eae49a48b6c379a5577b05db3910361498d571f0c9c46be2513',
		},
		{
			ArchiveId => "xtsSbQFG3BHgE9pk9ocSAXvpaNhXY9KwVUJjASW-5V3jzAbCjNzN5WlhQqcvRBsEUUa13OFc_9NIo2TIxCI6sumcdM5QC4wdL_uyhWxTpE8Bt5ODPchNhvnpeliMc0WnW4I01lA4Sw",
			ArchiveDescription => "mt2 textst",
			CreationDate => "2012-08-23T19:09:17Z",
			Size => 25000000,
			SHA256TreeHash => 'ef119aacb102f0c8790e0747a49f10e9b5d785656c04da3f069e6d26c7cc5818',
		},
		{
			ArchiveId => "OdEuDQOmt37jouhFioL-rleBdtLs4-e20FpQWwjp98XL0Ls5xRP9ghibqY_rrw07M9-_74LXRosXYsWXhPjaohxMeC02oGNA1SJU03rWibdye0BaNFsU8X5GYjGMNwmGDZF0whQxGg",
			ArchiveDescription => "",
			CreationDate => "2012-08-23T19:11:42Z",
			Size => 25000000,
			SHA256TreeHash => 'af119aacb102f0c8790e0747a49f10e9b5d785656c04da3f069e6d26c7cc5818',
		},
		{
			ArchiveId => "fH4iYmeZsnll5jwiO4aIIlHBEXZ5KjF-77hIz3TzPu3Ewjl1dxfhtEZWT2IteLjFHVhdrF2JctxhtRKsLmwenDuqBKj3iW-LYR1MXqkNJbaB4BTgnhCFoRkCmCA9rr-_Yr3CMJZoew",
			ArchiveDescription => "textstZ",
			CreationDate => "2012-08-23T19:20:08Z",
			Size => 25000000,
			SHA256TreeHash => 'ef119aacb102f0c8790e0747a49f10e9b5d785656c04da3f069e6d26c7cc5819',
		},
	];
}


{
	my $sample1 = <<'END';
{"VaultARN":"arn:aws:glacier:us-east-1:999966667777:vaults/test1","InventoryDate":"2013-11-06T02:51:29Z","ArchiveList":[
{"ArchiveId":"someid","ArchiveDescription":"","CreationDate":"somedate","Size":25000000,"SHA256TreeHash":"somehash"}
]}
END

	my $data = App::MtAws::Glacier::Inventory::JSON->new($sample1)->get_archives();
	is $data->[0]{ArchiveDescription}, "", "description can be empty string";
}

{
	my $obj;
	my $sample_r;
	{
	my $sample1 = <<'END';
{"VaultARN":"arn:aws:glacier:us-east-1:999966667777:vaults/test1","InventoryDate":"2013-11-06T02:51:29Z","ArchiveList":[
{"ArchiveId":"someid","ArchiveDescription":"somedescr","CreationDate":"somedate","Size":25000000,"SHA256TreeHash":"somehash"}
]}
END
	$sample_r = \$sample1;
	$obj = App::MtAws::Glacier::Inventory::JSON->new($sample1);
	weaken($sample_r);
	ok defined $sample_r;
	my $data = $obj->get_archives();
	is $data->[0]{ArchiveDescription}, "somedescr";
	}
	ok !defined $sample_r, "should save memory";
}

