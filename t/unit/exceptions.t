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
use Test::More tests => 150;
use Test::Deep;
use Encode;
use FindBin;
use Carp;
use POSIX;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::Exceptions;
use App::MtAws::Utils;
use I18N::Langinfo; # TODO: skip test without that module??




cmp_deeply exception('MyMessage'), { MTEXCEPTION => bool(1), message => 'MyMessage'};
cmp_deeply exception('mycode' => 'MyMessage'), { MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode'};
cmp_deeply exception('mycode' => 'MyMessage', myvar => 1),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', myvar => 1};
cmp_deeply exception('mycode' => 'MyMessage', myvar => 1, anothervar => 2),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', myvar => 1, anothervar => 2};
cmp_deeply exception('mycode' => 'MyMessage', code => 'code2'),
	{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'code2'};

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

# detecting wrong args
{
	ok ! eval { exception('mycode' => 'MyMessage', 'abc'); 1 };
	like $@, qr/Malformed exception/;

	ok ! eval { exception('mycode' => 'MyMessage', 'abc' => 'def', 'xyz'); 1 };
	like $@, qr/Malformed exception/;
}

# parsing args with errno ERRNO - unit
{
	no warnings 'redefine';
	local $! = EACCES;
	local *App::MtAws::Exceptions::get_errno = sub { "checkme" };
	cmp_deeply exception('mycode' => 'MyMessage', 'ERRNO'),
		{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', errno => "checkme", errno_code => EACCES+0 };
}
# parsing args with errno ERRNO - integration
{
	my $expect_errno = get_errno(POSIX::strerror(EACCES)); # real integration test with current locale
	local $! = EACCES;

	cmp_deeply exception('mycode' => 'MyMessage', 'ERRNO'),
		{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', errno => $expect_errno, errno_code => EACCES};

	cmp_deeply exception('mycode' => 'MyMessage', 'ERRNO', A => 123),
		{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', errno=> $expect_errno, errno_code => EACCES, A => 123};
	cmp_deeply exception('mycode' => 'MyMessage', A => 123, 'ERRNO'),
		{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', errno => $expect_errno, errno_code => EACCES, A => 123};
	cmp_deeply exception('mycode' => 'MyMessage', A => 123, 'ERRNO', B => 456),
		{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', errno => $expect_errno, errno_code => EACCES, A => 123, B => 456};


	local $! = EACCES;
	ok ! eval { exception('mycode' => 'MyMessage', ERRNO => 'xyz'); 1 };
	like $@, qr/Malformed exception/;

	local $! = EACCES;
	ok ! eval { exception('mycode' => 'MyMessage', 'ERRNO', A => 123, 'xyz'); 1 };
	like $@, qr/Malformed exception/;

	local $! = EACCES;
	ok ! eval { exception('mycode' => 'MyMessage', ERRNO => 'ERRNO'); 1 };
	like $@, qr/already used/i;

	local $! = EACCES;
	ok ! eval { exception('mycode' => 'MyMessage', 'ERRNO', x => 'y', 'ERRNO'); 1 };
	like $@, qr/already used/i;

	local $! = EACCES;
	cmp_deeply exception('mycode' => 'MyMessage', 'ERRNO', B => 'ERRNO'),
		{ MTEXCEPTION => bool(1), message => 'MyMessage', code => 'mycode', errno => $expect_errno, errno_code => EACCES, B => 'ERRNO'};

	my $r = exception('mycode' => 'MyMessage', 'ERRNO');
	{
		no warnings 'numeric';
		is $r->{errno}+1, 1, "strip magick";
	}
	is "$r->{errno_code}", EACCES, "strip magick";
}

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
	capture_stderr my $out, sub {
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

sub check_localized(&)
{
	local $@ = 'checkme';
	local $! = ENOMEM;
	shift->();
	is $@, 'checkme', "should not clobber eval error";
	is $!+0, ENOMEM, "should not clobber errno";
}

# test get_errno with argument
{
	for my $enc(qw/CP1251 KOI8-R UTF-8/) {
		local $App::MtAws::Exceptions::_errno_encoding = undef;
		my $test_str = "тест";
		my $bin_str = encode($enc, $test_str);
		no warnings 'redefine';

		local *I18N::Langinfo::langinfo = sub { $enc };
		check_localized {
			is get_errno($bin_str), $test_str, "get_errno (with arg) should work with encoding $enc";
		};

		local *I18N::Langinfo::langinfo = sub { confess };
		check_localized {
			is get_errno($bin_str), $test_str, "get_errno (with arg) should re-use encoding, $enc";
		};
	}
}

SKIP: {
	skip "Only for HP-UX", 3 if $^O ne 'hpux';
	my ($encode_enc, $i18_enc) = ('hp-roman8', 'roman8');
	local $App::MtAws::Exceptions::_errno_encoding = undef;
	my $test_str = "test";
	my $bin_str = encode($encode_enc, $test_str);
	no warnings 'redefine';

	local *I18N::Langinfo::langinfo = sub { $i18_enc };
	check_localized {
		is get_errno($bin_str), $test_str, "get_errno should work with roman8 encoding under HP-UX";
	};
	ok $App::MtAws::Exceptions::_errno_encoding, $encode_enc;
}

{
	local $App::MtAws::Exceptions::_errno_encoding = undef;
	my $test_str = encode("UTF-8", "тест");
	no warnings 'redefine';

	local *I18N::Langinfo::langinfo = sub { die };
	check_localized {
		is get_errno($test_str), hex_dump_string($test_str), "get_errno should work when CODESET crashed";
	};

	is $App::MtAws::Exceptions::_errno_encoding, App::MtAws::Exceptions::BINARY_ENCODING(),
		"should be a binary encoding, when CODESET crashed";

	local *I18N::Langinfo::langinfo = sub { "UTF-8" };
	check_localized {
		get_errno($test_str);
	};

	is $App::MtAws::Exceptions::_errno_encoding, App::MtAws::Exceptions::BINARY_ENCODING(),
		"BINARY encoding should be reused";
}

{
	local $App::MtAws::Exceptions::_errno_encoding = undef;
	my $test_str = encode("UTF-8", "тест");
	no warnings 'redefine';

	my $not_encoding = "NOT_AN_ENCODING";
	ok !defined find_encoding($not_encoding);

	local *I18N::Langinfo::langinfo = sub { $not_encoding };
	check_localized {
		is get_errno($test_str), hex_dump_string($test_str), "get_errno should work encoding is unknown";
	};

	is $App::MtAws::Exceptions::_errno_encoding, App::MtAws::Exceptions::BINARY_ENCODING(),
		"should be a binary encoding, when encoding is unknown";

	local *I18N::Langinfo::langinfo = sub { "UTF-8" };
	check_localized {
		get_errno($test_str);
	};

	is $App::MtAws::Exceptions::_errno_encoding, App::MtAws::Exceptions::BINARY_ENCODING(),
		"BINARY encoding should be reused";
}

{
	local $App::MtAws::Exceptions::_errno_encoding = undef;

	my $actual_encoding = 'KOI8-R';
	my $found_encoding = 'UTF-8';
	my $s = 'test тест';

	{
		my $bin = encode($actual_encoding, $s);
		ok ! eval { decode($found_encoding, $bin, Encode::DIE_ON_ERR|Encode::LEAVE_SRC); 1 };
	}

	my $test_str = encode($actual_encoding, $s);

	no warnings 'redefine';
	local *I18N::Langinfo::langinfo = sub { $found_encoding };
	check_localized {
		is get_errno($test_str), hex_dump_string($test_str), "get_errno should work encoding is incompatible";
	};

	is $App::MtAws::Exceptions::_errno_encoding, $found_encoding,
		"should NOT reset to binary encoding, when encoding is incompatible";

	local *I18N::Langinfo::langinfo = sub { $actual_encoding };
	check_localized {
		get_errno($test_str);
	};

	is $App::MtAws::Exceptions::_errno_encoding, $found_encoding,
		"should not be BINARY encoding";
}

{
	local $App::MtAws::Exceptions::_errno_encoding = undef;
	my $found_encoding = 'UTF-8';
	my $s = 'test тест';
	ok ! eval { decode($found_encoding, $s); 1 };
	ok utf8::is_utf8($s);
	no warnings 'redefine';
	local *I18N::Langinfo::langinfo = sub { $found_encoding };
	check_localized {
		# workaround issue https://rt.perl.org/rt3/Ticket/Display.html?id=119499
		is get_errno($s), $s, "get_errno should work ERRNO is character string";
	};

	is $App::MtAws::Exceptions::_errno_encoding, $found_encoding,
		"should NOT reset to binary encoding, when ERRNo is character string";

}

{
	ok ! defined find_encoding(App::MtAws::Exceptions::BINARY_ENCODING()),
		"BINARY_ENCODING should not be a valid encoding";
	ok App::MtAws::Exceptions::BINARY_ENCODING(), "BINARY_ENCODING should be TRUE";
}

{
	for my $err (EACCES, EAGAIN, ENOMEM, EEXIST) {
		local $App::MtAws::Exceptions::_errno_encoding = undef;
		local $! = $err;
		my $res_errno = get_errno($!);
		my $enc = $App::MtAws::Exceptions::_errno_encoding;

		my $expect = POSIX::strerror($err);
		check_localized { # dont use $! inside this block
			if ($enc eq App::MtAws::Exceptions::BINARY_ENCODING()) {
				is $res_errno, hex_dump_string($expect), "get_errno should work in real with real locales";
			} else {
				if (utf8::is_utf8($expect)) { # workaround issue https://rt.perl.org/rt3/Ticket/Display.html?id=119499
					is $res_errno, $expect, "get_errno should work in real with real locales";
				} else {
					is $res_errno, decode($enc, $expect), "get_errno should work in real with real locales";
				}
			}
		};
	}
}

1;
