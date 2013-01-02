#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 82;
use Test::Deep;
use lib qw{.. ../..};
use Journal;

# Filenames only, no directory name

for (qw!a a/b a/b/c!, qq! a/ b /c!, qq!a / c!, qq!0!, qq! 0!) {
	ok ( Journal::sanity_relative_filename($_) eq $_, "should not alter normal filenames $_");
}

for (qw!тест тест/тест тест/test тест/test/тест ф!) {
	ok ( Journal::sanity_relative_filename($_) eq $_, "should not alter normal UTF-8 filenames");
}

ok ( !defined Journal::sanity_relative_filename('/'), "should disallow empty path");
ok ( !defined Journal::sanity_relative_filename(''), "should disallow empty path");
ok ( !defined Journal::sanity_relative_filename('//'), "should disallow empty path");
ok ( !defined Journal::sanity_relative_filename('.'), "should disallow empty path");
ok ( !defined Journal::sanity_relative_filename('/.'), "should disallow empty path");
ok ( !defined Journal::sanity_relative_filename('./'), "should disallow empty path");


ok ( Journal::sanity_relative_filename('a/./b/./') eq 'a/b', "should delete more dots");
ok ( Journal::sanity_relative_filename('0/./b/./') eq '0/b', "should delete more dots");
ok ( Journal::sanity_relative_filename('ф/./b/./') eq 'ф/b', "should delete more dots");
ok ( Journal::sanity_relative_filename('a/./ф/./') eq 'a/ф', "should delete more dots");
ok ( Journal::sanity_relative_filename('a/./b/.') eq 'a/b', "should delete more dots");

ok ( Journal::sanity_relative_filename('/a') eq 'a', "should remove leading slash");
ok ( Journal::sanity_relative_filename('/0') eq '0', "should remove leading slash");
ok ( Journal::sanity_relative_filename('/ф') eq 'ф', "should remove leading slash");
ok ( Journal::sanity_relative_filename('/a/a') eq 'a/a', "should remove leading slash");
ok ( Journal::sanity_relative_filename('/ф/ф') eq 'ф/ф', "should remove leading slash");
ok ( Journal::sanity_relative_filename('/abc/d') eq 'abc/d', "should delete forward slash");
ok ( Journal::sanity_relative_filename('/abc/ф') eq 'abc/ф', "should delete forward slash");
ok ( Journal::sanity_relative_filename('/a ') eq 'a ', "should remove leading slash");
ok ( Journal::sanity_relative_filename('/ ') eq ' ', "should remove leading slash");

ok ( !defined Journal::sanity_relative_filename('../etc/password'), "should not allow two dots in path");
ok ( !defined Journal::sanity_relative_filename('/../etc/password'), "should not allow two dots in path");
ok ( !defined Journal::sanity_relative_filename('/../../etc/password'), "should not allow two dots in path");

ok ( !defined Journal::sanity_relative_filename('..'), "should not allow two dots in path");
ok ( !defined Journal::sanity_relative_filename('../'), "should not allow two dots in path");

ok ( !defined Journal::sanity_relative_filename('../'), "should not allow two dots in path");

ok ( Journal::sanity_relative_filename('ф..b') eq 'ф..b', "should allow two dots in name");
ok ( Journal::sanity_relative_filename('a..ф') eq 'a..ф', "should allow two dots in name");
ok ( Journal::sanity_relative_filename('a..b') eq 'a..b', "should allow two dots in name");
ok ( Journal::sanity_relative_filename('a..') eq 'a..', "should allow two dots in name");
ok ( Journal::sanity_relative_filename('ф..') eq 'ф..', "should allow two dots in name");
ok ( Journal::sanity_relative_filename('..a') eq '..a', "should allow two dots in name");
ok ( Journal::sanity_relative_filename('..ф') eq '..ф', "should allow two dots in name");
ok ( Journal::sanity_relative_filename(' ..a') eq ' ..a', "should allow two dots in name");
ok ( Journal::sanity_relative_filename(' ..ф') eq ' ..ф', "should allow two dots in name");
ok ( Journal::sanity_relative_filename(' ..a ') eq ' ..a ', "should allow two dots in name");
ok ( Journal::sanity_relative_filename(' ..ф ') eq ' ..ф ', "should allow two dots in name");
ok ( Journal::sanity_relative_filename(' ..0 ') eq ' ..0 ', "should allow two dots in name");

ok ( Journal::sanity_relative_filename('. ') eq '. ', "should allow two dots in name");
ok ( Journal::sanity_relative_filename(' .') eq ' .', "should allow two dots in name");
ok ( Journal::sanity_relative_filename('.. ') eq '.. ', "should allow two dots in name");
ok ( Journal::sanity_relative_filename(' ..') eq ' ..', "should allow two dots in name");

ok ( !defined Journal::sanity_relative_filename("a\nb"), "should not allow line");
ok ( !defined Journal::sanity_relative_filename("a\n"), "should not allow line");
ok ( !defined Journal::sanity_relative_filename("ф\nb"), "should not allow line");
ok ( !defined Journal::sanity_relative_filename("a\rb"), "should not carriage return");
ok ( !defined Journal::sanity_relative_filename("a\tb"), "should not allow tab");


ok ( ! defined Journal::sanity_relative_filename('//'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//..'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//../a'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//../../a'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//.././a'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//../ф'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//.'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//a'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//ф'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//./a'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//./ф'), "should deny two slashes");

ok ( ! defined Journal::sanity_relative_filename('//'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//..'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//../a'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//.'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//a'), "should deny two slashes");
ok ( ! defined Journal::sanity_relative_filename('//./a'), "should deny two slashes");

ok ( Journal::sanity_relative_filename('\\\\') eq '\\\\', "should allow backslash");
ok ( Journal::sanity_relative_filename('\\\\..') eq '\\\\..', "should allow backslash");
ok ( Journal::sanity_relative_filename('\\\\..\\a') eq '\\\\..\\a', "should allow backslash");
ok ( Journal::sanity_relative_filename('\\\\.') eq '\\\\.', "should allow backslash");
ok ( Journal::sanity_relative_filename('\\\\a') eq '\\\\a', "should allow backslash");
ok ( Journal::sanity_relative_filename('\\\\.\\a') eq '\\\\.\\a', "should allow backslash");

1;

