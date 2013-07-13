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
use Test::More tests => 276;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use Data::Dumper;
use App::MtAws::ConfigEngine;
use App::MtAws::Exceptions;
use App::MtAws::Utils;
use File::Path;
use Encode;
use POSIX;
use TestUtils;
use File::Temp ();

warning_fatal();

my $TEMP = File::Temp->newdir();
my $mtroot = $TEMP->dirname();
mkpath($mtroot);
my $file = "$mtroot/read-config-test.txt";
rmtree($file);

for my $linefeed ("\n", "\012", "\015\012") {
	my $vars = { 'mykey1' => 'myvalue1', 'mykey2' => 'myvalue2'};
	is_deeply(read_as_config("mykey1=myvalue1${linefeed}mykey2=myvalue2"), $vars, "should read different CR/LF");
	is_deeply(read_as_config("mykey1=myvalue1${linefeed}${linefeed}mykey2=myvalue2"), $vars, "should read different CR/LF");
	is_deeply(read_as_config("${linefeed}${linefeed}mykey1=myvalue1${linefeed}${linefeed}mykey2=myvalue2${linefeed}${linefeed}"), $vars, "should read different CR/LF");
}

for my $space (" ", "  ", "\t", " \t") {
	my $vars = { 'mykey1' => 'myvalue', 'mykey2' => 'myvalue2'};
	is_deeply(read_as_config("mykey1=myvalue${space}\nmykey2=myvalue2"), $vars, "should trim spaces");
	is_deeply(read_as_config("mykey1=${space}myvalue\nmykey2=myvalue2"), $vars, "should trim spaces");
	is_deeply(read_as_config("mykey1=myvalue\nmykey2${space}${space}=myvalue2"), $vars, "should trim spaces");
	is_deeply(read_as_config("mykey1=myvalue\nmykey2=myvalue2${space}"), $vars, "should trim spaces");
	is_deeply(read_as_config("${space}mykey1=myvalue\nmykey2=myvalue2"), $vars, "should trim spaces");

	is_deeply(read_as_config("mykey1${space}"), { mykey1 => 1}, "should trim spaces when no value");
	is_deeply(read_as_config("${space}mykey1"), { mykey1 => 1}, "should trim spaces when no value");
	is_deeply(read_as_config("${space}mykey1${space}"), { mykey1 => 1}, "should trim spaces when no value");
}


for my $notspace ("\xc2\xa0", "\xe2\x80\xaf", "\xc2\xa0\xe2\x80\xaf") {
	my $utfspace = decode("UTF-8", $notspace);
	ok ! defined eval { read_as_config("${notspace}mykey1"); 1 }, "should not trim unicode spaces when no value";
	is get_exception && get_exception->{code}, 'invalid_config_line';
	ok ! defined eval { read_as_config("mykey1${notspace}"); 1 }, "should not trim unicode spaces when no value";
	is get_exception && get_exception->{code}, 'invalid_config_line';
	ok ! defined eval { read_as_config("${notspace}mykey1${notspace}"); 1 }, "should not trim unicode spaces when no value";
	is get_exception && get_exception->{code}, 'invalid_config_line';

	ok ! defined eval { read_as_config("mykey1${notspace}=myvalue\nmykey2=myvalue2"); 1 }, "should not trim unicode spaces";
	is_deeply(
		read_as_config("mykey1=myvalue${notspace}\nmykey2=myvalue2"),
		{ 'mykey1' => "myvalue${utfspace}", 'mykey2' => 'myvalue2'},
		"should NOT trim unicode spaces"
	);
	is_deeply(
		read_as_config("mykey1=${notspace}myvalue\nmykey2=myvalue2"),
		{ 'mykey1' => "${utfspace}myvalue", 'mykey2' => 'myvalue2'},
		"should NOT trim unicode spaces"
	);
}

for my $badname ("!somename", 'some@name', 'some_name', '-somename', '--somename', '-', '--', '_', 'some-name-!', 'some name') {
	ok ! defined eval { read_as_config("$badname"); 1 }, "should deny invalid names";
	is get_exception && get_exception->{code}, 'invalid_config_line';
	ok ! defined eval { read_as_config(" $badname"); 1 }, "should deny invalid names";
	is get_exception && get_exception->{code}, 'invalid_config_line';
	ok ! defined eval { read_as_config("$badname=myvalue"); 1 }, "should deny invalid names";
	is get_exception && get_exception->{code}, 'invalid_config_line';
}

for my $goodname ("somename", 'some-name', 'some--name', 'SomeName', 'Some-Name', '1', '1name', '1-name', 'name-123') {
	is_deeply(read_as_config("$goodname=myvalue"), { $goodname => 'myvalue'}, "should accet correct names");
	is_deeply(read_as_config("$goodname"), { $goodname => 1}, "should accet correct names");
}

for my $badline ("x!=1", "тест=1", "test!1=тест") {
	my $utfbadline = encode("UTF-8", $badline);
	for my $append_lines (0..3) {
		my $wholefile = join("\n", (map { $_ } 1..$append_lines), $utfbadline);
		ok ! defined eval { read_as_config($wholefile); 1 };
		ok get_exception;
		is get_exception->{code}, 'invalid_config_line', "should have valid exception code";
		is get_exception->{lineno}, $append_lines + 1, "should report correct lineno";
		is get_exception->{line}, hex_dump_string($utfbadline), "should report correct line";
		is get_exception->{config}, hex_dump_string($file), "should report filename";
		is exception_message(get_exception),
			"Cannot parse line in config file: ".hex_dump_string($utfbadline	)." at ".hex_dump_string($file)." line ".($append_lines + 1);
	}
}


for my $utfstring ("тест", "вф") {
	is_deeply(
		read_as_config(encode("UTF-8", "mykey1=$utfstring")),
		{ 'mykey1' => $utfstring },
		"should read utf string"
	);
}

for my $comment (" ", "\t", "  ", "  \t", "#", " #", "# comment", "###", "             # comment", "\t#a=b", "\t\t#a=b", "\t#\ta=b") {
	my $vars = { 'mykey1' => 'myvalue', 'mykey2' => 'myvalue2'};
	is_deeply(read_as_config("mykey1=myvalue\n$comment\nmykey2=myvalue2"), $vars, "should allow comments in the beginning of line");
}

for my $notcomment ("#", " #", "# comment", "###", "             # comment", "\t#a=b", "\t\t#a=b", "\t#\ta=b") {
	my $vars = { 'mykey1' => 'myvalue'.$notcomment, 'mykey2' => 'myvalue2'};
	is_deeply(read_as_config("mykey1=myvalue$notcomment\nmykey2=myvalue2"), $vars, "should not allow comments in the midle of line");
}

for my $value ("a", "=b", "a=b", "c=d", "e==f", "===x") {
	my $vars = { 'mykey1' => 'myvalue'.$value, 'mykey2' => 'myvalue2'};
	is_deeply(read_as_config("mykey1=myvalue$value\nmykey2=myvalue2"), $vars, "should allow equal sign in values");
	my $vars2 = { 'mykey1' => $value, 'mykey2' => 'myvalue2'};
	is_deeply(read_as_config("mykey1=$value\nmykey2=myvalue2"), $vars2, "should allow equal sign in values");
}

{
	unlink $file if -e $file;
	ok ! -e $file, "assert we deleted file";
	my $C = App::MtAws::ConfigEngine->new();
	ok !defined eval { $C->read_config($file); 1 };
	ok get_exception;
	is get_exception->{code}, 'config_file_is_not_a_file';
	is get_exception->{config}, hex_dump_string($file);
	is exception_message(get_exception), "Config file is not a file: ".hex_dump_string($file);
}

{
	unlink $file;
	rmtree($file) if -d $file;
	mkpath($file);
	ok -d $file, "assert file is directory";
	my $C = App::MtAws::ConfigEngine->new();
	ok !defined eval { $C->read_config($file); 1;};
	ok get_exception;
	is get_exception->{code}, 'config_file_is_not_a_file';
	is get_exception->{config}, hex_dump_string($file);
	is exception_message(get_exception), "Config file is not a file: ".hex_dump_string($file);

}

sub read_as_config
{
	my ($bytes) = @_;
	open F, ">", $file;
	binmode F;
	print F $bytes;
	close F;
	my $C = App::MtAws::ConfigEngine->new();
	my $r = $C->read_config($file);
	return undef unless defined $r;
	return ({map { decode("UTF-8", $_)  } %$r}); # UTF-8 decode hash
}


1;
