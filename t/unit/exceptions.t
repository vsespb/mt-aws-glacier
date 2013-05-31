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
use Test::More tests => 65;
use Test::Deep;
use Encode;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Exceptions;
use TestUtils;

warning_fatal();


cmp_deeply exception('MyMessage'), { MTEXCEPTION => bool(1), message => 'MyMessage'};
cmp_deeply exception('mycode' => 'MyMessage'), { MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode'};
cmp_deeply exception('mycode' => 'MyMessage', myvar => 1),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', myvar => 1};
cmp_deeply exception('mycode' => 'MyMessage', myvar => 1, anothervar => 2),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', myvar => 1, anothervar => 2};
	
my $existing_exception = exception('xcode' => 'xmessage', myvar => 'xvar');

cmp_deeply exception($existing_exception, 'MyMessage'),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'xcode', myvar => 'xvar'};
cmp_deeply exception($existing_exception, 'mycode' => 'MyMessage'),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', myvar => 'xvar'};
cmp_deeply exception($existing_exception, 'mycode' => 'MyMessage', myvar => 1),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', myvar => 1};
cmp_deeply exception($existing_exception, 'mycode' => 'MyMessage', myvar2 => 1),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', myvar => 'xvar', myvar2=>1};
cmp_deeply exception($existing_exception, 'mycode' => 'MyMessage', myvar => 1, anothervar => 2),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', myvar => 1, anothervar => 2};


# get_exception

{
	eval { die exception('mycode' => 'MyMessage') };
	ok get_exception;
	is get_exception->{code}, 'mycode';
	is get_exception->{message}, 'MyMessage';
}

{
	eval { die exception('mycode' => 'MyMessage') };
	eval { 1; };
	ok $@ eq '';
	ok !get_exception;
}

{
	my $e = exception('mycode' => 'MyMessage');
	ok get_exception($e);
	is get_exception($e)->{code}, 'mycode';
	is get_exception($e)->{message}, 'MyMessage';
}

{
	ok !get_exception({});
	ok !get_exception('x');
	ok !get_exception([]);
	ok !get_exception({MTEXCEPTION=>0});
	ok get_exception({MTEXCEPTION=>1});
}

# is_exceptions

{
	eval { die exception('mycode' => 'MyMessage') };
	ok is_exception;
	ok !is_exception('mycode1');
	ok is_exception(undef);
	ok is_exception('mycode');
	ok !is_exception('zzz');
}

{
	eval { die exception('MyMessage') };
	ok !is_exception('mycode1');
	ok is_exception;
	ok is_exception(undef);
}
{
	my $e = exception('mycode' => 'MyMessage');
	ok is_exception('mycode', $e);
	ok is_exception(undef, $e);
	ok !is_exception('mycode1', $e);
	ok !is_exception('mycode', {});
}

# some integration testing

{
	unless (eval {
		unless (eval { die exception('mycode' => 'MyMessage'); 1 }) {
			if (is_exception 'mycode') {
				die exception get_exception, 'NewMessage'
			} else {
				die $@;
			}
		}
		1;
	}) {
		is get_exception->{message}, 'NewMessage'; # warning - must have test plan to test this way 
	}
}

{
	unless (eval {
		unless (eval { die exception('mycode' => 'MyMessage'); 1 }) {
			if (is_exception 'notmycode') {
				die exception get_exception, 'NewMessage'
			} else {
				die $@;
			}
		}
		1;
	}) {
		is get_exception->{message}, 'MyMessage';# warning - must have test plan to test this way
	}
}

{
	unless (eval {
		unless (eval { die "SomeString\n"; 1 }) {
			if (is_exception 'notmycode') {
				die exception get_exception, 'NewMessage'
			} else {
				die $@;
			}
		}
		1;
	}) {
		ok !get_exception;
		is $@, "SomeString\n";# warning - must have test plan to test this way
	}
}

# exception_message

is exception_message(exception 'code' => 'My message'), "My message", "should work without format";
is exception_message(exception 'code' => 'My message', filename => 'file1'), "My message", "should work without format, with params";
is exception_message(exception 'code' => 'My message %filename%', filename => 'file1'), "My message file1", "should work with one param";
is exception_message(exception 'code' => 'My message %filename% and %directory%', filename => 'file1', directory => 'dir1'),
	"My message file1 and dir1", "should work with two params";

is exception_message(exception 'code' => 'My message %s filename%', filename => 'file1'), "My message file1";
is exception_message(exception 'code' => 'My message %s filename% and %dir%', filename => 'file1', dir => 'dir1'), "My message file1 and dir1";
is exception_message(exception 'code' => 'My message %s filename% and %s dir%', filename => 'file1', dir => 'dir1'), "My message file1 and dir1";

is exception_message(exception 'code' => 'My message %string filename%', filename => 'file1'), 'My message "file1"';
is exception_message(exception 'code' => 'My message %string filename% and %string dir%', filename => 'file1', dir => 'dir1'),
	'My message "file1" and "dir1"';

is exception_message(exception 'code' => 'My message %04d x%', x => 42), 'My message 0042';
is exception_message(exception 'code' => 'My message %04d a_42%', a_42 => 42), 'My message 0042';

# confess tests

is 'My message :NULL:', exception_message(exception 'code' => 'My message %04d a_42%', b_42 => 42);
is 'My message :NULL:', exception_message(exception 'code' => 'My message %a_42%', b_42 => 42);
is 'My message :NULL:', exception_message(exception 'code' => 'My message %string a_42%', b_42 => 42);
ok exception_message(exception 'code' => 'My message %string a_42%', a_42 => 42, c_42=>33);


# dump_error


sub test_error(&$$)
{
	my ($cb, $where, $e) = @_;
	my $out=''; # perl 5.8.x issue warning if undefined $out is used in open() below
	capture_stderr $out, sub {
		eval { die $e };
		dump_error($where);
	};
	$cb->($out, $@);
}


test_error {
	my ($out, $err) = @_;
	cmp_deeply $err, superhashof { code => 'mycode',
		message => "MyMessage"};
	ok $out eq "ERROR: MyMessage\n";
} '', exception mycode => 'MyMessage';

test_error {
	my ($out, $err) = @_;
	cmp_deeply $err, superhashof { code => 'mycode',
		message => "MyMessage %errno%"};
	ok $out eq "ERROR: MyMessage 123\n";
} '', exception mycode => 'MyMessage %errno%', errno => 123;

test_error {
	my ($out, $err) = @_;
	cmp_deeply $err, superhashof { code => 'mycode',
		message => "MyMessage"};
	ok $out eq "ERROR (here): MyMessage\n";
} 'here', exception mycode => 'MyMessage';

test_error {
	my ($out, $err) = @_;
	cmp_deeply $err, superhashof { code => 'cmd_error',
		message => "MyMessage"};
	ok !defined($out) || length($out) == 0;
} '', exception cmd_error => 'MyMessage';

test_error {
	my ($out, $err) = @_;
	cmp_deeply $err, superhashof { code => 'cmd_error',
		message => "MyMessage"};
	ok !defined($out) || length($out) == 0;
} 'here', exception cmd_error => 'MyMessage';

test_error {
	my ($out, $err) = @_;
	ok $out =~ /^UNEXPECTED ERROR: somestring/;
} '', 'somestring';

test_error {
	my ($out, $err) = @_;
	ok $out =~ /^UNEXPECTED ERROR \(here\): somestring/;
} 'here', 'somestring';


	# TODO: check also that 'next' is called!



1;

