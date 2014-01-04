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
use Test::More tests => 1069;
use Test::Deep;
use Encode;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::Filter;
use Data::Dumper;
use TestUtils;

warning_fatal();

# to make sure we're not affected by
# http://perldoc.perl.org/perl5180delta.html#New-Restrictions-in-Multi-Character-Case-Insensitive-Matching-in-Regular-Expression-Bracketed-Character-Classes
my %special_chars = ( # KEY should match KEY but should not match VALUE
	'ss' => 'ß',
	'ß' => 'ss',
);

is length('ß'), 1; # make sure we're running unicode

#
# _filters_to_pattern
#

sub assert_parse_filter_error($$)
{
	my ($data, $err) = @_;
	my $F = App::MtAws::Filter->new();
	ok ! defined $F->_filters_to_pattern($data);
	is $F->{error}, $err;
}

sub assert_parse_filter_ok(@)
{
	my ($expected, @data) = (pop, @_);
	my $F = App::MtAws::Filter->new();
	ok !$F->{error};
	cmp_deeply [$F->_filters_to_pattern(@data)], $expected;
}


my @spaces = ('', ' ', '  ');
my @onespace = ('', ' ');

for my $before (@spaces) {
	for my $after (@spaces) {
		for my $sign (qw/+ -/) {
			for my $last (@spaces) {
				assert_parse_filter_ok "${before}${sign}${after}*.gz${last}", [{ action => $sign, pattern =>'*.gz'}];
			}
		}
	}
}

for my $exclamation ('', '!') {
	for my $between (' ', '  ') {
		for my $before (@onespace) {
			for my $after (@onespace) {
				for my $last (@onespace) {
					my ($res, $err);

					assert_parse_filter_ok "${before}+${after}${exclamation}*.gz${last}${between}${before}-${after}*.txt${last}",
						[{ action => '+', pattern => "${exclamation}*.gz"}, { action => '-', pattern => '*.txt'}];

					assert_parse_filter_ok
						"${before}+${after}${exclamation}*.gz${last}${between}${before}-${after}*.txt${last}",
						"${before}-${after}*.jpeg${last}${between}${before}+${after}*.png${last}",
						[{ action => '+', pattern => "${exclamation}*.gz"}, { action => '-', pattern => '*.txt'},
						{ action => '-', pattern => '*.jpeg'}, { action => '+', pattern => '*.png'}];

					assert_parse_filter_ok
						"${before}+${after}${exclamation}*.gz${last}${between}${before}-${after}*.txt${last}",
						"${before}-${after}*.jpeg${last}${between}",
						[{ action => '+', pattern => "${exclamation}*.gz"}, { action => '-', pattern => '*.txt'}, { action => '-', pattern => '*.jpeg'}];

					assert_parse_filter_ok
						"${between}${before}-${after}*.txt${last}",
						"${before}-${after}*.jpeg${last}${between}${before}+${after}*.png${last}",
						[{ action => '-', pattern => '*.txt'}, { action => '-', pattern => '*.jpeg'}, { action => '+', pattern => '*.png'}];
				}
			}
		}
	}
}

assert_parse_filter_ok "+", [ { action => '+', pattern => ''} ];
assert_parse_filter_ok "-", [ { action => '-', pattern => ''} ];
assert_parse_filter_ok "+data/ -", [ { action => '+', pattern => 'data/'}, { action => '-', pattern => ''} ];
assert_parse_filter_ok "++", [ { action => '+', pattern => '+'} ];
assert_parse_filter_ok "+++", [ { action => '+', pattern => '++'} ];
assert_parse_filter_ok "--", [ { action => '-', pattern => '-'} ];
assert_parse_filter_ok "---", [ { action => '-', pattern => '--'} ];
assert_parse_filter_ok "+ ", [ { action => '+', pattern => ''} ];
assert_parse_filter_ok " + ", [ { action => '+', pattern => ''} ];
assert_parse_filter_ok "  +  ", [ { action => '+', pattern => ''} ];

assert_parse_filter_ok "-+", [ { action => '-', pattern => '+'} ];
assert_parse_filter_ok "+-", [ { action => '+', pattern => '-'} ];

assert_parse_filter_ok "-data/  +  ", [  { action => '-', pattern => 'data/'}, { action => '+', pattern => ''} ];
assert_parse_filter_ok "-data/  +", [  { action => '-', pattern => 'data/'}, { action => '+', pattern => ''} ];
assert_parse_filter_ok "-data/  ++", [  { action => '-', pattern => 'data/'}, { action => '+', pattern => '+'} ];
assert_parse_filter_ok "-data/  -+", [  { action => '-', pattern => 'data/'}, { action => '-', pattern => '+'} ];


for my $first (qw/+ -/) {
	for my $second (qw/+ -/) {
		for my $before (@spaces) {
			for my $after (@spaces) {
				assert_parse_filter_ok "${second}*data/ ${before}${first}${after}${second}${before}",
					[  { action => $second, pattern => '*data/'}, { action => $first, pattern => $second} ];
			}
		}
	}
}

assert_parse_filter_error ' +z  p +a', 'p +a';
assert_parse_filter_error '+z z', 'z';
assert_parse_filter_error '', '';
assert_parse_filter_error ' ', ' ';

#
# _patterns_to_regexp regexp correctness
#

sub check
{
	my ($filter, %lists) = @_;
	my $F = App::MtAws::Filter->new();
	my ($re) = $F->_patterns_to_regexp({pattern => $filter});
	for (@{$lists{ismatch}}) {
		my $orig_utf_flag = utf8::is_utf8($_);
		$_ = "/$_";
		is utf8::is_utf8($_), $orig_utf_flag;
		ok $re->{notmatch} ? ($_ !~ $re->{re}) : ($_ =~ $re->{re}), "[$filter], [$re->{re}],$_";
	}
	for (@{$lists{nomatch}}) {
		my $orig_utf_flag = utf8::is_utf8($_);
		$_ = "/$_";
		is utf8::is_utf8($_), $orig_utf_flag;

		#print Dumper $re;
		ok $re->{notmatch} ? ($_ =~ $re->{re}) : ($_ !~ $re->{re}), "[$filter], [$re->{re}], $_";
	}
}

check 'file', ismatch => ['file', 'x/file', 'x/y/file'], nomatch => ['filex', 'xfile'];

# wildcard, any dir
check '*.gz', ismatch => ['1.gz', 'a/1.gz', 'b/c/d/22.gz', '.gz', 'a/.gz'];

check '*img*',
	ismatch => ['img', 'img_01.jpeg', 'x_img_01.jpeg', 'a/img_01.jpeg', 'b/c/the_img_01.jpeg', 'b/c/img_01.jpeg'],
	nomatch => ['im/g', 'imxg'];

check 'img*',
	ismatch => ['img', 'img_01.jpeg', 'a/img_01.jpeg',  'b/c/img_01.jpeg'],
	nomatch => ['im/g', 'b/c/the_img_01.jpeg'];

for (sort keys %special_chars) {
	check "x$_*",
		ismatch => ["x$_", "x${_}01.jpeg", "a/x${_}_01.jpeg",  "b/c/x${_}_01.jpeg"],
		nomatch => ["x$special_chars{$_}", "x$special_chars{$_}_01.jpeg", "a/x$special_chars{$_}_01.jpeg",  "b/c/x$special_chars{$_}_01.jpeg"];
}

# '?' wildcard

check '??.gz',
	ismatch => ['12.gz', 'a/34.gz', 'b/c/d/xy.gz'],
	nomatch => ['123.gz', '1.gz', 'a/345.gz', 'b/c/d/p.gz'];

check 'x?z.gz',
	ismatch => ['xyz.gz', 'a/xpz.gz', 'b/c/d/xxz.gz'],
	nomatch => ['xz.gz', 'a/xDDz.gz', 'b/c/d/ppz.gz'];

check 'a/?',
	ismatch => ['a/1', 'a/2', 'a/3'],
	nomatch => ['a/11', 'a1', 'a/123'];

# file, any dir
check '.gitignore',
	ismatch => ['.gitignore', 'a/.gitignore', 'b/c/.gitignore'],
	nomatch => ['p.gitignore', 'p.gitignorex', 'a/x.gitignore', 'a/.gitignorep', 'b/c/x.gitignore', 'b/c/.gitignorep'];

check 'example.txt',
	ismatch => ['a/example.txt', 'b/c/example.txt', 'example.txt'],
	nomatch => ['xexample.txt', 'a/xexample.txt', 'example.txtA', 'b/c/example.txtP'];

# directory at a specific location
check '/data/',
	ismatch => [qw!data/ data/1 data/y/x!],
	nomatch => [qw!data!];

check '/tmp/a',
	ismatch => ['tmp/a'];

# file, at a specific location
check '/data',
	ismatch => [qw!data!],
	nomatch => [qw!data/ data/1 data/y/x!];

check 'tmp/a',
	ismatch => ['tmp/a'],
	nomatch => ['tmp/ab', 'xtmp/a'];

# directory, any location
check '.git/',
	ismatch => [qw!.git/ .git/a x/.git/a x/.git/ x/.git/b/c x/y/.git/p x/y/.git/r/r!],
	nomatch => [qw!.git x/.git x/y/.git!];

check '!.git/',
	nomatch => [qw!.git/ .git/a x/.git/a x/.git/ x/.git/b/c x/y/.git/p x/y/.git/r/r!],
	ismatch => [qw!.git x/.git x/y/.git!];

# wildcard, specific location
check '/var/log/*.log',
	ismatch => ['var/log/abc.log', 'var/log/def.log'],
	nomatch => ['var/logx/abc.log', 'var/x/log/def.log'];

check 'tmp/a*',
	ismatch => ['tmp/a', 'tmp/ab'],
	nomatch => ['tmp/a/x', 'tmp/ab/x'];

# two stars

check 'tmp/a**',
	ismatch => ['tmp/a/x', 'tmp/a'];

check 'tmp/a/**',
	ismatch => ['tmp/a/'],
	nomatch => ['tmp/ab', 'tmp/ab/x'];

check 'tmp/**',
	ismatch => ['tmp/a', 'tmp/ab', 'tmp/ab/x', 'tmp/a/x'],
	nomatch => [];

check '**/tmp/**',
	ismatch => ['x/tmp/z', 'x/tmp/a',            'tmp/a/', 'tmp/ab', 'tmp/ab/x', 'tmp/a/x'],
	nomatch => ['p/xtmp'];

check '**/.gitignore',
	ismatch => ['.gitignore', 'a/.gitignore', 'b/c/.gitignore'],
	nomatch => [];

check '!**/.gitignore',
	nomatch => ['.gitignore', 'a/.gitignore', 'b/c/.gitignore'],
	ismatch => [];

# two stars in the beginning or end of filename
check 'foo/**/bar',
	ismatch => ['foo/bar', 'foo/1/bar', 'foo/1/2/bar'],
	nomatch => ['foobar', 'foox/bar', 'foo/xbar'];

check 'foo**/bar',
	ismatch => ['foo/bar', 'foo/1/bar', 'foox/bar', 'foox/1/bar'],
	nomatch => ['foobar', 'foo/xbar', 'foox/xbar'];

check 'foo/**bar',
	ismatch => ['foo/bar', 'foo/1/bar', 'foo/xbar', 'foo/1/xbar'],
	nomatch => ['foobar', 'foox/bar', 'foox/xbar'];

check '**/bar',
	ismatch => ['bar', 'foo/bar', 'foo/1/bar'],
	nomatch => ['1/xbar', 'xbar', 'bar/', 'foo/bar/', 'foo/1/bar/'];

check '**bar',
	ismatch => ['bar', 'foo/bar', 'foo/1/bar', '1/xbar', 'xbar'],
	nomatch => ['bar/', 'foo/bar/', 'foo/1/bar/'];

check 'bar**',
	ismatch => ['bar/1', 'bar/', 'bar/1/2/3', 'barx/', 'barx/1', 'bary', 'bar'],
	nomatch => ['zbar'];
# /


check '**/tmp',
	ismatch => [],
	nomatch => ['p/xtmp'];

check '**/*tmp',
	ismatch => ['p/xtmp', 'tmp', 'ztmp'],
	nomatch => [];

check 'tmp**',
	ismatch => ['tmpz', 'tmp/z', 'tmpz/z', 'tmp/z', 'x/tmpz', 'x/tmpz/z'],
	nomatch => ['ptmpz'];

check 'a/tmp**',
	ismatch => ['a/tmpz', 'a/tmp/z', 'a/tmpz/z', 'a/tmp/z'],
	nomatch => ['a/ptmpz'];

check '/tmp**',
	ismatch => ['tmpz', 'tmp/z', 'tmpz/z', 'tmp/z', ],
	nomatch => ['ptmpz', 'x/tmpz', 'x/tmpz/z'];

check '!/tmp**',
	nomatch => ['tmpz', 'tmp/z', 'tmpz/z', 'tmp/z', ],
	ismatch => ['ptmpz', 'x/tmpz', 'x/tmpz/z'];

check 'example',
	ismatch => ['example'],
	nomatch => ['tmp/example/a'];

check 'z/example',
	ismatch => ['z/example'],
	nomatch => ['tmp/pz/example/a'];


for my $s ("\xB5", "\xDF") { # Latin1
	ok ord($s) > 127;
	ok ord($s) <= 255;

	for my $u1 (0, 1) {
		my $s1 = $s;
		$u1 ? utf8::downgrade($s1) : utf8::upgrade($s1);
		for my $u2 (0, 1) {
			my $s2 = $s;
			$u2 ? utf8::downgrade($s2) : utf8::upgrade($s2);

			ok $s1 eq $s;
			ok $s1 eq $s2;

			check $s1,
				ismatch => [$s2],
				nomatch => ["tmp/$s2/a"];
		}
	}
}


# check empty pattern

check '',
	ismatch => ['a', 'a/b', 'a/b/c'];

my $a = 123;

$a =~ /123/;
check '',
	ismatch => ['a', 'a/b', 'a/b/c'];

$a =~ /4/;
check '',
	ismatch => ['a', 'a/b', 'a/b/c'];

#
# _patterns_to_regexp match_subdirs
#


for ('', 'a/', '/a/', 'a/b/', '/a/b/', '**', '/**', '/a/**', 'a**', 'a/b/**', 'a/b**') {
	my $F = App::MtAws::Filter->new();
	my ($re) = $F->_patterns_to_regexp({pattern => $_});
	ok $re->{match_subdirs}, "match subdirs [$_]";
}

for (' ', 'a/ ', '/a/ ', 'a/b/ ', '/a/b/ ', '*', '/*', '/a/*', 'a*', 'a/b/* *', 'a/b** *', 'a/b**c') {
	my $F = App::MtAws::Filter->new();
	my ($re) = $F->_patterns_to_regexp({pattern => $_});
	ok !$re->{match_subdirs}, "does not match subdirs [$_]";
}


#
# _patterns_to_regexp correctness of escapes
#


check 'z/ex.mple',
	ismatch => ['z/ex.mple'],
	nomatch => ['z/exNmple'];

check 'z/ex\\dmple',
	ismatch => ['z/ex\\dmple'],
	nomatch => ['z/ex1mple'];

check 'z/ex{1,2}mple',
	ismatch => ['z/ex{1,2}mple'],
	nomatch => ['z/exmple', 'z/exxmple'];

check 'z/ex[1|2]mple',
	ismatch => ['z/ex[1|2]mple'],
	nomatch => ['z/ex2mple', 'z/ex1mple'];

# simply test with fixtures

{
	my $F = {};
	App::MtAws::Filter::_init_substitutions($F, "\Q**\E" => '.*', "\Q*\E" => '[^/]*');
	is $F->{all_re}, '(\\\\\\*\\\\\\*|\\\\\\*)';
	cmp_deeply $F->{subst}, {'\\*' => '[^/]*','\\*\\*' => '.*'}, "substitutions work";

	$F = {};
	App::MtAws::Filter::_init_substitutions($F, "\Q*\E" => '[^/]*');
	is $F->{all_re}, '(\\\\\\*)';
	cmp_deeply $F->{subst}, {'\\*' => '[^/]*'}, "substitutions work";
}


#
# parse_filters
#

# simply test with fixtures

{
	my $F = App::MtAws::Filter->new();
	$F->parse_filters('-abc -dir/ +*.gz', '-!*.txt');
	cmp_deeply $F->{filters},
	[
		{
			'pattern' => 'abc',
			're' => qr/(^|\/)abc$/,
			'action' => '-',
			'match_subdirs' => '',
			'notmatch' => '',
		},
		{
			'pattern' => 'dir/',

			# Test::Deep problem here https://rt.cpan.org/Ticket/Display.html?id=85785
			# looks like perl 5.8.x issue with regexp stringification
			're' => do { my $s = '(^|/)dir\/'; qr/$s/ },

			'action' => '-',
			'match_subdirs' => 1,
			'notmatch' => '',
		},
		{
			'pattern' => '*.gz',
			're' => qr/(^|\/)[^\/]*\.gz$/,
			'action' => '+',
			'match_subdirs' => '',
			'notmatch' => '',
		},
		{
			'pattern' => '!*.txt',
			're' => qr/(^|\/)[^\/]*\.txt$/,
			'action' => '-',
			'match_subdirs' => '',
			'notmatch' => '1',
		}
	];
}
#
# parse_include
#

{
	my $F = App::MtAws::Filter->new();
	$F->parse_include('*.gz');
	cmp_deeply $F->{filters},[{
		'pattern' => '*.gz',
		'notmatch' => bool(0),
		're' => qr/(^|\/)[^\/]*\.gz$/,
		'action' => '+',
		'match_subdirs' => bool(0)
	}];
}

{
	my $F = App::MtAws::Filter->new();
	$F->parse_include('!*.gz');
	cmp_deeply $F->{filters}, [{
		'pattern' => '!*.gz',
		'notmatch' => bool(1),
		're' => qr/(^|\/)[^\/]*\.gz$/,
		'action' => '+',
		'match_subdirs' => bool(0)
	}];
}

{
	my $F = App::MtAws::Filter->new();
	$F->parse_exclude('*.gz');
	cmp_deeply $F->{filters},[{
		'pattern' => '*.gz',
		'notmatch' => bool(0),
		're' => qr/(^|\/)[^\/]*\.gz$/,
		'action' => '-',
		'match_subdirs' => bool(0)
	}];
}

{
	my $F = App::MtAws::Filter->new();
	$F->parse_exclude('!*.gz');
	cmp_deeply $F->{filters}, [{
		'pattern' => '!*.gz',
		'notmatch' => bool(1),
		're' => qr/(^|\/)[^\/]*\.gz$/,
		'action' => '-',
		'match_subdirs' => bool(0)
	}];
}

#
# check_filenames
#

sub test_check_filenames
{
	my ($filters, $list, $expected, $msg) = @_;
	my $F = App::MtAws::Filter->new();
	$F->parse_filters($filters);
	ok ! defined $F->{error};
	cmp_deeply [$F->check_filenames(@$list)], $expected, $msg;
}


test_check_filenames '+*.gz -/data/ +', [qw{1.gz 1.txt data/1.txt data/z/1.txt data/2.gz f data/p/33.gz}],
	[qw{1.gz 1.txt data/2.gz f data/p/33.gz}], "should work";
test_check_filenames '-/data/ +*.gz -', [qw{1.gz p/1.gz data/ data/1.gz data/a/1.gz}], [qw{1.gz p/1.gz}], "should work again";
test_check_filenames '+*.gz -/data/', [qw{1.gz 1.txt data/1.txt data/z/1.txt data/2.gz f data/p/33.gz}],
	[qw{1.gz 1.txt data/2.gz f data/p/33.gz}], "default action - include";
test_check_filenames '+*.gz +/data/ -', [qw{x/y x/y/z.gz /data/1 /data/d/2 abc}],  [qw{x/y/z.gz /data/1 /data/d/2}], "default action - exclude";
test_check_filenames '-!/data/ +*.gz +/data/backup/ -',
	[qw{data/1 dir/1.gz data/2 data/3.gz data/x/4.gz data/backup/5.gz data/backup/6/7.gz data/backup/z/1.txt}],
	[qw{data/3.gz data/x/4.gz data/backup/5.gz data/backup/6/7.gz data/backup/z/1.txt}], "exclamation mark should work";
test_check_filenames '-0.* -фexclude/a/ +*.gz -', [qw{fexclude/b фexclude/b.gz}], [qw{фexclude/b.gz}],  "exclamation mark should work";

#
# check_dir
#

sub test_check_dir
{
	my ($filters, $dir, $res, $subdirs) = @_;
	my $F = App::MtAws::Filter->new();
	$F->parse_filters($filters);
	ok ! defined $F->{error};
	cmp_deeply [$F->check_dir($dir)], [bool($res), bool($subdirs)]
}

test_check_dir '+*.gz -/data/ +', 'data/', 0, 0;
test_check_dir '-/data/ +*.gz +', 'data/', 0, 1;
test_check_dir '+*.gz -/data** +', 'datadir/', 0, 0;
test_check_dir '-/data** +*.gz +', 'datadir/', 0, 1;
test_check_dir '-*.gz -/data** +', 'datadir/', 0, 1;
test_check_dir '-/data** -*.gz -/data** +', 'datadir/', 0, 1;
test_check_dir '+1.txt -*.gz -/data** +', 'datadir/', 0, 0;
test_check_dir '-1.txt -*.gz +/data** +', 'datadir/', 1, 0;
test_check_dir '+/data/ -', 'data/', 1, 0;
test_check_dir '+!/data/ -', 'somedir/', 1, 0;
test_check_dir '-!/data/ +', 'somedir/', 0, 0;
test_check_dir '-!/data/ +', 'somedir/', 0, 0;
test_check_dir '-/data/a/ +', 'data/', 1, 0;
test_check_dir '-/data/a/ +', 'data/a/', 0, 1;


1;
