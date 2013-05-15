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
use Test::More tests => 34;
use Test::Deep;
use Encode;
use lib qw{../lib ../../lib};
use App::MtAws::Exceptions;


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
		is get_exception->{message}, 'NewMessage';
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
		is get_exception->{message}, 'MyMessage';
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
		is $@, "SomeString\n";
	}
}

1;

