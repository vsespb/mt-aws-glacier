#!/usr/bin/perl

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
use Test::More tests => 62;
use Test::Deep;
use Carp;
use Encode;
use FindBin;
use POSIX;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use Data::Dumper;

# before 'use xxx Utils'

BEGIN { *CORE::GLOBAL::sysread = sub(*\$$;$) { &_sysread; }; };
BEGIN { *CORE::GLOBAL::syswrite = sub(*$;$$) { &_syswrite; }; };

use App::MtAws::Utils;
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
	sub _sysread(*\$$;$)
	{
		confess unless @queue;
		my $pos = $_[3]||0;
		${$_[1]} = '' unless defined ${$_[1]};
		my $q = shift @queue;
		$! = 0;
		return 0 if $q eq 'EOF';
		return undef if $q eq 'ERR';
		if ($q eq 'EINTR') {
			$! = EINTR;
			return undef;
		}
		my $len = length( ${$_[1]} );
		${$_[1]} .= "0" x ( $pos - $len ) if $len < $pos; # original syswrite uses 0x00

		substr(${$_[1]}, $pos) = $q;
		confess if length $q > $_[2];
		length $q;
	};

	# test the test - how our test code _sysread works
	{
		local @queue;
		ok ! defined eval { _sysread($in, my $x, 1); 1 };
	}
	{
		local @queue = qw/EOF/;
		is _sysread($in, my $x, 1), 0;
		is $x, '';
		ok !$!;
	}
	{
		local @queue = qw/ERR/;
		is _sysread($in, my $x, 1), undef;
		is $x, '';
		ok !$!;
	}
	{
		local @queue = qw/EINTR/;
		is _sysread($in, my $x, 1), undef;
		is $x, '';
		ok $!{EINTR};
	}
	{
		local @queue = qw/a/;
		is _sysread($in, my $x, 1), 1;
		is $x, 'a';
		ok !$!;
	}
	{
		local @queue = qw/a/;
		is _sysread($in, my $x, 1, 1), 1;
		is $x, '0a';
		ok !$!;
	}
	{
		local @queue = qw/d/;
		my $x = 'abc';
		is _sysread($in, $x, 1, 3), 1;
		is $x, 'abcd';
		ok !$!;
	}

	# actual test
	{
		local @queue = ('ab');
		is sysreadfull($in, my $x, 2), 2;
		is $x, 'ab', "should work in simple case";
	}
	{
		local @queue = ('a', 'bc');
		is sysreadfull($in, my $x, 3), 3;
		is $x, 'abc', "should work with two reads";
	}
	{
		local @queue = ('ab', 'c', 'de');
		is sysreadfull($in, my $x, 5), 5;
		is $x, 'abcde', "should work with three reads";
	}
	{
		local @queue = ('ab', 'c', 'de');
		is sysreadfull($in, my $x, 5), 5;
		is $x, 'abcde', "should work with three reads";
	}
	{
		local @queue = ('ab', 'c', 'EOF');
		is sysreadfull($in, my $x, 5), 3;
		is $x, 'abc', "should work with eof in the middle";
	}
	{
		local @queue = ('EOF');
		is sysreadfull($in, my $x, 5), 0;
		is $x, '', "should work with eof in the beginning";
	}
	{
		local @queue = ('ERR');
		is sysreadfull($in, my $x, 5), undef;
		is $x, '', "should work with ERROR in the beginning";
	}
	{
		local @queue = ('ab', 'c', 'ERR', 'ERR');
		is sysreadfull($in, my $x, 5), 3;
		is $x, 'abc', "should work with ERROR in the middle";
		is sysreadfull($in, my $y, 5), undef;
	}
	{
		local @queue = ('ab', 'c', 'EINTR', 'de');
		is sysreadfull($in, my $x, 5), 5;
		is $x, 'abcde', "should work with EINTR in the middle";
	}
	{
		local @queue = ('ab', 'c', 'EINTR', 'd', 'EOF');
		is sysreadfull($in, my $x, 5), 4;
		is $x, 'abcd', "should work with EINTR in the middle, when there will be eof";
	}
	{
		local @queue = ('ab', 'c', 'EINTR', 'd', 'ERR');
		is sysreadfull($in, my $x, 5), 4;
		is $x, 'abcd', "should work with EINTR in the middle, when there will be ERROR";
	}
	{
		local @queue = ('EINTR', 'ab', 'c', 'EINTR', 'EINTR', 'd', 'EINTR', 'ERR');
		is sysreadfull($in, my $x, 5), 4;
		is $x, 'abcd', "should work with several EINTR";
	}
	{
		local @queue = ('ab', 'EINTR', 'EINTR', 'c', 'd', 'EINTR', 'EOF');
		is sysreadfull($in, my $x, 5), 4;
		is $x, 'abcd', "should work with several EINTR";
	}

	sub _syswrite(*$;$$)
	{
		confess unless @queue;
		my $q = shift @queue;
		my $code = shift @queue;
		confess unless defined $code;
		my ($len, $offset) = ($_[2], $_[3]);
		confess if $offset + $len > length $_[1];
		my $data = substr $_[1], $offset, $len;
		confess unless $data eq $q;
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

	}

	{
		local @queue = (abcd => 4);
		is syswritefull($in, "abcd"), 4, "should work";
	}
	{
		local @queue = (abcd => 3, d => 1);
		is syswritefull($in, "abcd"), 4, "should work when partial write";
	}
	{
		local @queue = (abcd => 2, cd => 1, d => 1);
		is syswritefull($in, "abcd"), 4, "should work when many partial writes";
	}
	{
		local @queue = (abcd => 0, abcd => 0, abcd => 4);
		is syswritefull($in, "abcd"), 4, "should work with zero-writes";
	}
	{
		local @queue = (abcd => 'ERR');
		is syswritefull($in, "abcd"), undef, "should work with ERR";
	}
	{
		local @queue = (abcd => 2, cd => 'ERR');
		# I am not enterelly sure if real syswrite acts like this!
		is syswritefull($in, "abcd"), 2, "should work with ERR after data";
	}
	{
		local @queue = (abcd => 2, cd => 0, cd => 'ERR');
		is syswritefull($in, "abcd"), 2, "should work with ERR after data";
	}
	{
		local @queue = (abcd => 'EINTR', abcd => 'ERR');
		is syswritefull($in, "abcd"), undef, "should work with ERR after EINTR";
	}
	{
		local @queue = (abcd => 'EINTR', abcd => 0, abcd => 'ERR');
		is syswritefull($in, "abcd"), undef, "should work with ERR after EINTR";
	}
	{
		local @queue = ('тест' => 1);
		ok ! defined eval { syswritefull($in, "abcd"); 1 }, "should confess if wide chars";
	}
	{
		local @queue = ('µµµµ' => 1);
		ok ! defined eval { syswritefull($in, "abcd"); 1 }, "should confess if Latin-1 chars";
	}
	{
		my ($str, undef) = split ' ', "some тест";
		is $str, "some";
		ok utf8::is_utf8($str);
		local @queue = ($str => length $str);
		is syswritefull($in, $str), length($str), "should work with ASCII with utf-8 bit set";
	}
	{
		my $str = encode("UTF-8", "тест");
		ok !utf8::is_utf8($str);
		local @queue = ($str => length $str);
		is syswritefull($in, $str), length($str), "should work with ASCII with utf-8 bit set";
	}
}


1;

