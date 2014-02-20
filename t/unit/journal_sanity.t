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
use utf8;
use Test::More tests => 5238;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::Utils;


# Filenames only, no directory name

for (qw!a a/b a/b/c!, qq! a/ b /c!, qq!a / c!, qq!0!, qq! 0!) {
	ok ( App::MtAws::Utils::sanity_relative_filename($_) eq $_, "should not alter normal filenames $_");
}

for (qw!тест тест/тест тест/test тест/test/тест ф!) {
	ok ( App::MtAws::Utils::sanity_relative_filename($_) eq $_, "should not alter normal UTF-8 filenames");
}

ok ( !defined App::MtAws::Utils::sanity_relative_filename(), "should disallow undef");
ok ( !defined App::MtAws::Utils::sanity_relative_filename('/'), "should disallow empty path");
ok ( !defined App::MtAws::Utils::sanity_relative_filename(''), "should disallow empty path");
ok ( !defined App::MtAws::Utils::sanity_relative_filename('//'), "should disallow empty path");
ok ( !defined App::MtAws::Utils::sanity_relative_filename('.'), "should disallow empty path");
ok ( !defined App::MtAws::Utils::sanity_relative_filename('/.'), "should disallow empty path");
ok ( !defined App::MtAws::Utils::sanity_relative_filename('./'), "should disallow empty path");


ok ( App::MtAws::Utils::sanity_relative_filename('a/./b/./') eq 'a/b', "should delete more dots");
ok ( App::MtAws::Utils::sanity_relative_filename('0/./b/./') eq '0/b', "should delete more dots");
ok ( App::MtAws::Utils::sanity_relative_filename('ф/./b/./') eq 'ф/b', "should delete more dots");
ok ( App::MtAws::Utils::sanity_relative_filename('a/./ф/./') eq 'a/ф', "should delete more dots");
ok ( App::MtAws::Utils::sanity_relative_filename('a/./b/.') eq 'a/b', "should delete more dots");

ok ( App::MtAws::Utils::sanity_relative_filename('/a') eq 'a', "should remove leading slash");
ok ( App::MtAws::Utils::sanity_relative_filename('/0') eq '0', "should remove leading slash");
ok ( App::MtAws::Utils::sanity_relative_filename('/ф') eq 'ф', "should remove leading slash");
ok ( App::MtAws::Utils::sanity_relative_filename('/a/a') eq 'a/a', "should remove leading slash");
ok ( App::MtAws::Utils::sanity_relative_filename('/ф/ф') eq 'ф/ф', "should remove leading slash");
ok ( App::MtAws::Utils::sanity_relative_filename('/abc/d') eq 'abc/d', "should delete forward slash");
ok ( App::MtAws::Utils::sanity_relative_filename('/abc/ф') eq 'abc/ф', "should delete forward slash");
ok ( App::MtAws::Utils::sanity_relative_filename('/a ') eq 'a ', "should remove leading slash");
ok ( App::MtAws::Utils::sanity_relative_filename('/ ') eq ' ', "should remove leading slash");

ok ( !defined App::MtAws::Utils::sanity_relative_filename('../etc/password'), "should not allow two dots in path");
ok ( !defined App::MtAws::Utils::sanity_relative_filename('/../etc/password'), "should not allow two dots in path");
ok ( !defined App::MtAws::Utils::sanity_relative_filename('/../../etc/password'), "should not allow two dots in path");

ok ( !defined App::MtAws::Utils::sanity_relative_filename('..'), "should not allow two dots in path");
ok ( !defined App::MtAws::Utils::sanity_relative_filename('../'), "should not allow two dots in path");

ok ( !defined App::MtAws::Utils::sanity_relative_filename('../'), "should not allow two dots in path");

ok ( App::MtAws::Utils::sanity_relative_filename('ф..b') eq 'ф..b', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename('a..ф') eq 'a..ф', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename('a..b') eq 'a..b', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename('a..') eq 'a..', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename('ф..') eq 'ф..', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename('..a') eq '..a', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename('..ф') eq '..ф', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename(' ..a') eq ' ..a', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename(' ..ф') eq ' ..ф', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename(' ..a ') eq ' ..a ', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename(' ..ф ') eq ' ..ф ', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename(' ..0 ') eq ' ..0 ', "should allow two dots in name");

ok ( App::MtAws::Utils::sanity_relative_filename('. ') eq '. ', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename(' .') eq ' .', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename('.. ') eq '.. ', "should allow two dots in name");
ok ( App::MtAws::Utils::sanity_relative_filename(' ..') eq ' ..', "should allow two dots in name");

ok ( !defined App::MtAws::Utils::sanity_relative_filename("a\nb"), "should not allow line");
ok ( !defined App::MtAws::Utils::sanity_relative_filename("a\n"), "should not allow line");
ok ( !defined App::MtAws::Utils::sanity_relative_filename("ф\nb"), "should not allow line");
ok ( !defined App::MtAws::Utils::sanity_relative_filename("a\rb"), "should not carriage return");
ok ( !defined App::MtAws::Utils::sanity_relative_filename("a\tb"), "should not allow tab");


ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//..'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//../a'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//../../a'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//.././a'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//../ф'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//.'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//a'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//ф'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//./a'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//./ф'), "should deny two slashes");

ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//..'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//../a'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//.'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//a'), "should deny two slashes");
ok ( ! defined App::MtAws::Utils::sanity_relative_filename('//./a'), "should deny two slashes");


SKIP: {
	skip "backslash allowed under cygwin", 6 if $^O eq 'cygwin';
	ok ( App::MtAws::Utils::sanity_relative_filename('\\\\') eq '\\\\', "should allow backslash");
	ok ( App::MtAws::Utils::sanity_relative_filename('\\\\..') eq '\\\\..', "should allow backslash");
	ok ( App::MtAws::Utils::sanity_relative_filename('\\\\..\\a') eq '\\\\..\\a', "should allow backslash");
	ok ( App::MtAws::Utils::sanity_relative_filename('\\\\.') eq '\\\\.', "should allow backslash");
	ok ( App::MtAws::Utils::sanity_relative_filename('\\\\a') eq '\\\\a', "should allow backslash");
	ok ( App::MtAws::Utils::sanity_relative_filename('\\\\.\\a') eq '\\\\.\\a', "should allow backslash");
};

# is_relative_filename

for (qw!a a/b a/b/c!, qq! a/ b /c!, qq!a / c!, qq!0!, qq! 0!) {
	ok ( App::MtAws::Utils::is_relative_filename($_), "should work with normal filenames $_");
}

for (qw!тест тест/тест тест/test тест/test/тест ф!) {
	ok ( App::MtAws::Utils::is_relative_filename($_), "should work with normal UTF-8 filenames");
}

ok ( !App::MtAws::Utils::is_relative_filename(), "should disallow undef");
ok ( !App::MtAws::Utils::is_relative_filename('/'), "should disallow empty path");
ok ( !App::MtAws::Utils::is_relative_filename(''), "should disallow empty path");
ok ( !App::MtAws::Utils::is_relative_filename('//'), "should disallow empty path");
ok ( !App::MtAws::Utils::is_relative_filename('.'), "should disallow empty path");
ok ( !App::MtAws::Utils::is_relative_filename('/.'), "should disallow empty path");
ok ( !App::MtAws::Utils::is_relative_filename('./'), "should disallow empty path");


ok ( !App::MtAws::Utils::is_relative_filename('a/./b/./'), "should disallow more dots");
ok ( !App::MtAws::Utils::is_relative_filename('0/./b/./'), "should disallow more dots");
ok ( !App::MtAws::Utils::is_relative_filename('ф/./b/./'), "should disallow more dots");
ok ( !App::MtAws::Utils::is_relative_filename('a/./ф/./'), "should disallow more dots");
ok ( !App::MtAws::Utils::is_relative_filename('a/./b/.') , "should disallow more dots");

ok ( !App::MtAws::Utils::is_relative_filename('/a'), "should disallow leading slash");
ok ( !App::MtAws::Utils::is_relative_filename('/0'), "should disallow leading slash");
ok ( !App::MtAws::Utils::is_relative_filename('/ф'), "should disallow leading slash");
ok ( !App::MtAws::Utils::is_relative_filename('/a/a'), "should disallow leading slash");
ok ( !App::MtAws::Utils::is_relative_filename('/ф/ф'), "should disallow leading slash");
ok ( !App::MtAws::Utils::is_relative_filename('/abc/d'), "should disallow forward slash");
ok ( !App::MtAws::Utils::is_relative_filename('/abc/ф'), "should disallow forward slash");
ok ( !App::MtAws::Utils::is_relative_filename('/a '), "should disallow leading slash");
ok ( !App::MtAws::Utils::is_relative_filename('/ '), "should disallow leading slash");

ok ( !App::MtAws::Utils::is_relative_filename('../etc/password'), "should not allow two dots in path");
ok ( !App::MtAws::Utils::is_relative_filename('/../etc/password'), "should not allow two dots in path 2");
ok ( !App::MtAws::Utils::is_relative_filename('/../../etc/password'), "should not allow two dots in path");

ok ( !App::MtAws::Utils::is_relative_filename('..'), "should not allow two dots in path");
ok ( !App::MtAws::Utils::is_relative_filename('../'), "should not allow two dots in path");

ok ( !App::MtAws::Utils::is_relative_filename('../'), "should not allow two dots in path");

ok ( App::MtAws::Utils::is_relative_filename('ф..b'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename('a..ф'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename('a..b'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename('a..'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename('ф..'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename('..a'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename('..ф'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename(' ..a'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename(' ..ф'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename(' ..a '), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename(' ..ф '), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename(' ..0 '), "should allow two dots in name");

ok ( App::MtAws::Utils::is_relative_filename('. '), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename(' .'), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename('.. '), "should allow two dots in name");
ok ( App::MtAws::Utils::is_relative_filename(' ..'), "should allow two dots in name");

ok ( !App::MtAws::Utils::is_relative_filename("a\nb"), "should not allow line");
ok ( !App::MtAws::Utils::is_relative_filename("a\n"), "should not allow line");
ok ( !App::MtAws::Utils::is_relative_filename("ф\nb"), "should not allow line");
ok ( !App::MtAws::Utils::is_relative_filename("a\rb"), "should not carriage return");
ok ( !App::MtAws::Utils::is_relative_filename("a\tb"), "should not allow tab");


ok ( !App::MtAws::Utils::is_relative_filename('//'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//..'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//../a'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//../../a'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//.././a'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//../ф'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//.'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//a'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//ф'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//./a'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//./ф'), "should deny two slashes");

ok ( !App::MtAws::Utils::is_relative_filename('//'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//..'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//../a'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//.'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//a'), "should deny two slashes");
ok ( !App::MtAws::Utils::is_relative_filename('//./a'), "should deny two slashes");

SKIP: {
	skip "backslash allowed under cygwin", 6 if $^O eq 'cygwin';
	ok ( App::MtAws::Utils::is_relative_filename('\\\\'), "should allow backslash");
	ok ( App::MtAws::Utils::is_relative_filename('\\\\..'), "should allow backslash");
	ok ( App::MtAws::Utils::is_relative_filename('\\\\..\\a'), "should allow backslash");
	ok ( App::MtAws::Utils::is_relative_filename('\\\\.'), "should allow backslash");
	ok ( App::MtAws::Utils::is_relative_filename('\\\\a'), "should allow backslash");
	ok ( App::MtAws::Utils::is_relative_filename('\\\\.\\a'), "should allow backslash");
}

ok ( App::MtAws::Utils::is_relative_filename('0'), "should allow last component to be false");
ok ( App::MtAws::Utils::is_relative_filename('0/0'), "should allow last component to be false");


# again, stresstestingm just in case

my @valid_components = (qw/ф 0 a abc µ µµ µФ/, "\\", "\\\\");
my @spaces = map ' ' x $_, 1..4;

my @dots = ('.', '..', '...', '....');
for my $good (
	@valid_components, @spaces,
	(map {
		my $dot = $_;
		map {
			("$_$dot", "$dot$_", "$dot$_$dot");
		} @spaces, @valid_components;
	} @dots ),
) {
	ok is_relative_filename($good);
	ok is_relative_filename("$good/$good");
	ok is_relative_filename("$good/");
	ok is_relative_filename("$good/$good/");

	for my $bad (
		"/$good",
		(map { ("$good/$_", "$good/$_/", "$_/$good", "$_/$good/", "a/$_/$good", "a/$_/$good/")  } ('.', '..')),
	) {
		ok ! is_relative_filename($_);
		my $s = App::MtAws::Utils::sanity_relative_filename($_);
		ok !defined($s) || ($s ne $_);
	}
}

1;

