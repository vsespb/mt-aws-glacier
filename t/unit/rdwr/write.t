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
use Test::More tests => 18;
use Test::Deep;
use Carp;
use Encode;
use FindBin;
use POSIX;
use lib map { "$FindBin::RealBin/$_" } qw{../../lib ../../../lib};
use Data::Dumper;

use App::MtAws::RdWr::Write;
use TestUtils;

my $mtroot = get_temp_dir();
open(my $tmp, ">", "$mtroot/infile") or confess;
close $tmp;
open(my $in, "<", "$mtroot/infile") or confess;

warning_fatal();

{
	no warnings 'redefine';

	our @queue;
	local $!;

	local *App::MtAws::RdWr::Write::_syswrite = sub {
		confess unless @queue;
		my $q = shift @queue;
		my $code = shift @queue;
		confess unless defined $code;
		my ($len, $offset) = ($_[2], $_[3]);
		confess "$offset + $len > ".length($_[1]) if $offset + $len > length $_[1];
		my $data = substr $_[1], $offset, $len;
		confess "$data eq $q" unless $data eq $q;
		$!=0;
		return length $data if $code eq 'OK';
		if ($code eq 'ERR') {
			return undef;
		}
		if ($code eq 'EINTR') {
			$! = EINTR;
			return undef;
		}
		return $code; # a number

	};

	sub wr
	{
		App::MtAws::RdWr::Write->new($in);
	}

	{
		local @queue = (abcd => 4);
		is wr->syswritefull("abcd"), 4, "should work";
	}
	{
		local @queue = (abcd => 3, d => 1);
		is wr->syswritefull("abcd"), 4, "should work when partial write";
	}
	{
		local @queue = (abcd => 2, cd => 1, d => 1);
		is wr->syswritefull("abcd"), 4, "should work when many partial writes";
	}
	{
		local @queue = (abcd => 0, abcd => 0, abcd => 4);
		is wr->syswritefull("abcd"), 4, "should work with zero-writes";
	}
	{
		local @queue = (abcd => 'ERR');
		is wr->syswritefull("abcd"), undef, "should work with ERR";
	}
	{
		local @queue = (abcd => 2, cd => 'ERR');
		# I am not enterelly sure if real syswrite acts like this!
		is wr->syswritefull("abcd"), 2, "should work with ERR after data";
	}
	{
		local @queue = (abcd => 2, cd => 0, cd => 'ERR');
		is wr->syswritefull("abcd"), 2, "should work with ERR after data";
	}
	{
		local @queue = (abcd => 'EINTR', abcd => 'ERR');
		is wr->syswritefull("abcd"), undef, "should work with ERR after EINTR";
	}
	{
		local @queue = (abcd => 'EINTR', abcd => 0, abcd => 'ERR');
		is wr->syswritefull("abcd"), undef, "should work with ERR after EINTR";
	}
	{
		local @queue = ('тест' => 4);
		ok ! defined eval { wr->syswritefull("тест"); 1 }, "should confess if wide chars";
		like "$@", qr/upgraded strings not allowed/;
	}
	{
		local @queue = ('µµµµ' => 1);
		ok ! defined eval { wr->syswritefull("µµµµ"); 1 }, "should confess if Latin-1 chars";
		like "$@", qr/upgraded strings not allowed/;
	}
	{
		my ($str, undef) = split ' ', "some тест";
		is $str, "some";
		ok utf8::is_utf8($str);
		local @queue = ($str => length $str);
		is wr->syswritefull($str), length($str), "should work with ASCII with utf-8 bit set";
	}
	{
		my $str = encode("UTF-8", "тест");
		ok !utf8::is_utf8($str);
		local @queue = ($str => length $str);
		is wr->syswritefull($str), length($str), "should work with ASCII with utf-8 bit set";
	}
}


1;
