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
	my %h = ();
	my $rr = rr(\%h);
	ok ! defined $rr->next_key;
	my @a = $rr->next_key;
	ok !@a;
	ok ! defined $rr->next_value;
	my @b = $rr->next_value;
	ok !@b;
}

{
	my %h = ('a' => 42);
	my $rr = rr(\%h);
	is $rr->next_key, 'a';
	is $rr->next_key, 'a';
}


{
	my %h = ();
	my $rr = rr(\%h);
	$h{a}=1;
	is $rr->next_key, 'a';
	$h{b}=1;
	is $rr->next_key, 'b';
	is $rr->next_key, 'a';
	is $rr->next_key, 'b';
}

{
	my %h = ();
	my $rr = rr(\%h);
	$h{a}=1;
	is $rr->next_key, 'a';
	delete $h{a};
	ok ! defined $rr->next_key;
}

{
	my %h = ();
	my $rr = rr(\%h);
	$h{a}=1;
	is $rr->next_key, 'a';
	$h{b}=1;
	is $rr->next_key, 'b';
	delete $h{a};
	is $rr->next_key, 'b', "should work if current key removed";
	is $rr->next_key, 'b';
}

{
	my %h = ();
	my $rr = rr(\%h);
	$h{a}=1;
	is $rr->next_key, 'a';
	$h{b}=1;
	is $rr->next_key, 'b';
	cmp_deeply $rr->{indices}, [qw/b a/];
	delete $h{b};
	is $rr->next_key, 'a', "should work if previous key removed";
	is $rr->next_key, 'a';
}

{
	my %h = ();
	my $rr = rr(\%h);
	$h{a}=1;
	is $rr->next_key, 'a';
	$h{b}=1;
	is $rr->next_key, 'b';
	cmp_deeply $rr->{indices}, [qw/b a/];
	is $rr->next_key, 'a';
	delete $h{a};
	is $rr->next_key, 'b', "should work if previous key removed, and previous key is above current";
	is $rr->next_key, 'b';
}

{
	my %h = ();
	my $rr = rr(\%h);
	$h{a}=1;
	is $rr->next_key, 'a';
	$h{b}=1;
	is $rr->next_key, 'b';
	cmp_deeply $rr->{indices}, [qw/b a/];
	is $rr->next_key, 'a';
	delete $h{b};
	is $rr->next_key, 'a';
}

1;
