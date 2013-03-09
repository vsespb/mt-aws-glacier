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
use Test::More tests => 234;
use Test::Deep;
use Encode;
use lib qw{../lib ../../lib};
use App::MtAws::Filter qw/_filters_to_pattern parse_filters _filters_to_regexp/;
use Data::Dumper;


#
# _parse_filters
#

sub assert_parse_filter_error($$)
{
	my ($data, $err) = @_;
	cmp_deeply [_filters_to_pattern($data)], [undef, $err];
}

sub assert_parse_filter_ok(@$)
{
	my ($expected, @data) = (pop, @_);
	cmp_deeply [_filters_to_pattern(@data)], [$expected, undef];
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

for my $between (' ', '  ') {
	for my $before (@onespace) {
		for my $after (@onespace) {
			for my $last (@onespace) {
				my ($res, $err);
				
				assert_parse_filter_ok "${before}+${after}*.gz${last}${between}${before}-${after}*.txt${last}",
					[{ action => '+', pattern => '*.gz'}, { action => '-', pattern => '*.txt'}];
				
				assert_parse_filter_ok
					"${before}+${after}*.gz${last}${between}${before}-${after}*.txt${last}",
					"${before}-${after}*.jpeg${last}${between}${before}+${after}*.png${last}",
					[{ action => '+', pattern => '*.gz'}, { action => '-', pattern => '*.txt'},
					{ action => '-', pattern => '*.jpeg'}, { action => '+', pattern => '*.png'}];

				assert_parse_filter_ok
					"${before}+${after}*.gz${last}${between}${before}-${after}*.txt${last}",
					"${before}-${after}*.jpeg${last}${between}",
					[{ action => '+', pattern => '*.gz'}, { action => '-', pattern => '*.txt'}, { action => '-', pattern => '*.jpeg'}];
				
				assert_parse_filter_ok
					"${between}${before}-${after}*.txt${last}",
					"${before}-${after}*.jpeg${last}${between}${before}+${after}*.png${last}",
					[{ action => '-', pattern => '*.txt'}, { action => '-', pattern => '*.jpeg'}, { action => '+', pattern => '*.png'}];
			}
		}
	}
}


assert_parse_filter_error ' +z  p +a', 'p +a';
assert_parse_filter_error '+z z', 'z';
assert_parse_filter_error '', '';
assert_parse_filter_error ' ', ' ';

sub check
{
	my ($filter, %lists) = @_;
	my ($re) = _filters_to_regexp({pattern => $filter});
	for (@{$lists{ismatch}}) {
		$_ = "/$_";
		ok $_ =~ $re->{re}, "[$filter], [$re->{re}],$_";
	}
	for (@{$lists{nomatch}}) {
		$_ = "/$_";
		ok $_ !~ $re->{re}, "[$filter], [$re->{re}], $_";
	}
}

# wildcard, any dir
check '*.gz', ismatch => ['1.gz', 'a/1.gz', 'b/c/d/22.gz', '.gz', 'a/.gz'];

check '*img*',
	ismatch => ['img', 'img_01.jpeg', 'x_img_01.jpeg', 'a/img_01.jpeg', 'b/c/the_img_01.jpeg', 'b/c/img_01.jpeg'],
	nomatch => ['im/g', 'imxg'];

check 'img*',
	ismatch => ['img', 'img_01.jpeg', 'a/img_01.jpeg',  'b/c/img_01.jpeg'],
	nomatch => ['im/g', 'b/c/the_img_01.jpeg'];


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

check 'example',
	ismatch => [],
	nomatch => ['tmp/example/a'];
	
check 'z/example',
	ismatch => [],
	nomatch => ['tmp/pz/example/a'];
	
check '',
	ismatch => ['a', 'a/b', 'a/b/c'];
		

1;
__END__
check '??',
	ismatch => [],
	nomatch => [];
