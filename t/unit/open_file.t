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
use Test::More tests => 50;
use Test::Deep;
use Encode;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use Data::Dumper;
use File::Path;

our $OpenStack = undef;
our $BinmodeStack = undef;

# before 'use xxx Utils'
sub _open { CORE::open($_[0], $_[1], $_[2]) };
BEGIN { *CORE::GLOBAL::open = sub(*;$@) { push @$OpenStack, \@_; _open(@_) }; };
BEGIN { *CORE::GLOBAL::binmode = sub(*;$) { push @$BinmodeStack, \@_; CORE::binmode($_[0]) }; };

use App::MtAws::Utils;
use App::MtAws::Exceptions;
use TestUtils;

warning_fatal();


my $mtroot = get_temp_dir();
my $tmp_file = "$mtroot/open_file_test";

unlink $tmp_file;
rmtree $tmp_file;


sub new_stack(&)
{
	local $OpenStack = [];
	local $BinmodeStack = [];
	shift->();
}

sub last_call()
{
	$OpenStack->[0]
}


#
# mode
#

ok ! defined eval { open_file(my $f, $tmp_file); 1};
ok $@ =~ /Argument "mode" is required/;

ok ! defined eval { open_file(my $f, $tmp_file, mode => 'x'); 1};
ok $@ =~ /unknown mode/;

{
	ok open_file(my $f, $tmp_file, mode => '>', binary => 1);
}

new_stack {
	ok open_file(my $f, $tmp_file, mode => '>', binary => 1);
	is '>', last_call->[1]
};

new_stack {
	ok open_file(my $f, $tmp_file, mode => '>>', binary => 1);
	is '>>', last_call->[1]
};

new_stack {
	ok open_file(my $f, $tmp_file, mode => '>>', binary => 1);
	is '>>', last_call->[1]
};

new_stack {
	ok open_file(my $f, $tmp_file, mode => '+>>', binary => 1);
	is '+>>', last_call->[1]
};

new_stack {
	ok open_file(my $f, $tmp_file, mode => '+<', binary => 1);
	is '+<', last_call->[1]
};

new_stack {
	create_tmp_file();
	ok open_file(my $f, $tmp_file, mode => '<', binary => 1);
	is '<', last_call->[1]
};

#
# other args
#

ok ! defined eval { open_file(my $f, $tmp_file, mode => '>', binary => 1, zz => 123); 1};
ok $@ =~ /Unknown argument/;

#
# not_empty
#

ok ! defined eval { open_file(my $f, $tmp_file, mode => '>', binary => 1, not_empty => 1); 1};
ok $@ =~ /not_empty can be used in read mode only/;

create_tmp_file();
ok defined eval { open_file(my $f, $tmp_file, mode => '<', binary => 1, not_empty => 1); 1};
unlink $tmp_file;

#
# binary and file_encoding
#

ok ! defined eval { open_file(my $f, $tmp_file, mode => '>', binary => 1, file_encoding => 'UTF-8'); 1};
ok $@ =~ /cannot use binary and file_encoding at same time/;

ok ! defined eval { open_file(my $f, $tmp_file, mode => '>'); 1};
ok $@ =~ /there should be file encoding or 'binary'/;

new_stack {
	ok open_file(my $f, $tmp_file, mode => '>', binary => 1);
	ok @$BinmodeStack;
	unlink $tmp_file;
};

new_stack {
	ok open_file(my $f, $tmp_file, mode => '>', file_encoding => 'UTF-8');
	is '>:encoding(UTF-8)', last_call->[1];
	ok !@$BinmodeStack;
	unlink $tmp_file;
};

new_stack {
	ok open_file(my $f, $tmp_file, mode => '>', file_encoding => 'KOI8-R');
	is '>:encoding(KOI8-R)', last_call->[1];
	ok !@$BinmodeStack;
	unlink $tmp_file;
};

{
	create_tmp_file(encode("UTF-8", "тест"));
	ok open_file(my $f, $tmp_file, mode => '<', file_encoding => 'UTF-8');
	my $line = <$f>;
	is $line, 'тест';
	unlink $tmp_file;
}

{
	create_tmp_file(my $encoded = encode("UTF-8", "тест"));
	ok open_file(my $f, $tmp_file, mode => '<', binary => 1);
	my $line = <$f>;
	is $line, $encoded;
	unlink $tmp_file;
}

#
# use_filename_encoding
#

new_stack {
	my $utfname = $mtroot."/тест";
	eval { open_file(my $f, $utfname, mode => '>', binary => 1); };
	is last_call->[2], encode("UTF-8", $utfname), "should use filename_ecnoding by default";
};

new_stack {
	my $utfname = $mtroot."/тест";
	eval { open_file(my $f, $utfname, mode => '>', binary => 1, use_filename_encoding => 1); };
	is last_call->[2], encode("UTF-8", $utfname), "should use filename_ecnoding";
};

new_stack {
	local $App::MtAws::Utils::_filename_encoding = 'KOI8-R';
	is get_filename_encoding, 'KOI8-R';
	my $utfname = $mtroot."/тест";
	eval { open_file(my $f, $utfname, mode => '>', binary => 1, use_filename_encoding => 1); };
	is last_call->[2], encode("KOI8-R", $utfname), "should use filename_ecnoding when it's not UTF";
};


new_stack {
	my $utfname = $mtroot."/тест";
	eval { open_file(my $f, $utfname, mode => '>', binary => 1, use_filename_encoding => 0); };
	is last_call->[2], $utfname, "should not use filename_ecnoding";
};

#
# should work
#

{
	create_tmp_file("123");
	open_file(my $f, $tmp_file, mode => '<', binary => 1);
	my @a = <$f>;
	cmp_deeply [@a], ['123'];
}

#
# file checks
#

{
	unlink $tmp_file;
	mkpath $tmp_file;
	ok ! defined eval { open_file(my $f, $tmp_file, mode => '>', binary => 1); 1 };
	ok $@ =~ /not a plain file/i;
	rmtree $tmp_file;
}

{
	create_tmp_file("");
	ok ! defined eval { open_file(my $f, $tmp_file, mode => '<', binary => 1, not_empty=>1); 1 };
	ok $@ =~ /should not be empty/i;
	unlink $tmp_file;
}


unlink $tmp_file;
{
	ok ! defined open_file(my $f, $tmp_file, mode => '<', binary => 1);
}

ok defined eval { open_file(my $f, $tmp_file, mode => '>', binary => 1); 1};
unlink $tmp_file;

unlink $tmp_file;


sub create_tmp_file
{
	CORE::open F, ">", $tmp_file;
	binmode F;
	print F @_ ? shift : "1\n";
	close F;

}

1;

