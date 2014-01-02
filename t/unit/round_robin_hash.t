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
use Test::More tests => 32;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::RoundRobinHash;
use Data::Dumper;
use TestUtils;

warning_fatal();

sub rr
{
	App::MtAws::RoundRobinHash->new(@_);
}

{
	my $rr = rr;
	ok ! defined $rr->current();
	ok ! defined $rr->current(0);
	ok ! defined $rr->current(1);
}

{
	my $rr = rr;
	$rr->add('a');
	is $rr->current, 'a';
	is $rr->current, 'a';
	is $rr->current(0), 'a';
	ok ! defined $rr->current(1);
}


{
	my $rr = rr;
	$rr->add('a');
	$rr->add('b');
	is $rr->current, 'a';
	is $rr->current, 'a';
	is $rr->current(0), 'a';
	is $rr->current(1), 'b';
	ok ! defined $rr->current(2);
}

{
	my $rr = rr;
	$rr->add('a');
	$rr->add('b');
	is $rr->current, 'a';
	is $rr->current, 'a';
	$rr->remove('a');
	is $rr->current, 'b';
	is $rr->current(0), 'b';
	ok ! defined $rr->current(1);
}

{
	my $rr = rr;
	$rr->add('a');
	$rr->add('b');
	is $rr->current, 'a';
	is $rr->current, 'a';
	is $rr->current(0), 'a';
#	exit;
#	print Dumper $rr;
	is $rr->current(1), 'b';
#	print Dumper $rr;
	$rr->next_key(1);
#	print Dumper $rr;
	is $rr->current, 'b';
	is $rr->current(0), 'b';
#	print Dumper $rr;
	is $rr->current(1), 'a';
#	print Dumper $rr;
	ok ! defined $rr->current(2);
}

{
	my $rr = rr;
	$rr->add('a');
	$rr->add('b');
	is $rr->current(0), 'a';
	is $rr->current(1), 'b';
	$rr->move_to_tail(0);
	is $rr->current(0), 'b';
}

{
	my $rr = rr;
	$rr->add('a');
	$rr->add('b');
	is $rr->current(0), 'a';
	is $rr->current(1), 'b';
	$rr->move_to_tail(1);
	is $rr->current(0), 'a';
	is $rr->current(1), 'b';
}
1;
