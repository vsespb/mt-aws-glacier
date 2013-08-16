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
use warnings FATAL => 'all';
use utf8;
use open qw/:std :utf8/;
use Encode;
use Test::More tests => 381;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::ConfigEngine;
use Carp;
use Data::Dumper;
use TestUtils;

warning_fatal();
no warnings 'redefine';

# validation

{
	my $c  = create_engine();
	$c->define(sub {
		option('myoption');
		validation 'myoption', message('too_high', "%option a% should be less than 30"), sub { $_ < 30 };
		command 'mycommand' => sub { validate(optional('myoption')), ok !valid('myoption'); };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31);
	cmp_deeply $res->{error_texts}, [q{"--myoption" should be less than 30}], "validation should work";
	cmp_deeply $res->{errors}, [{format => 'too_high', a => 'myoption', value => 31}], "validation should work";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option('myoption', alias => 'old');
		validation 'myoption', message('too_high', "%option a% should be less than 30"), sub { $_ < 30 };
		command 'mycommand' => sub { validate optional('myoption') };
	});
	my $res = $c->parse_options('mycommand', '-old', 31);
	cmp_deeply $res->{error_texts}, [q{"--old" should be less than 30}], "validation should work with alias";
	cmp_deeply $res->{errors}, [{format => 'too_high', a => 'old', value => 31}], "validation should work with alias";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option('myoption', deprecated => 'old');
		validation 'myoption', message('too_high', "%option a% should be less than 30"), sub { $_ < 30 };
		command 'mycommand' => sub { validate optional('myoption') };
	});
	my $res = $c->parse_options('mycommand', '-old', 31);
	cmp_deeply $res->{error_texts}, [q{"--old" should be less than 30}], "validation should work with deprecated";
	cmp_deeply $res->{errors}, [{format => 'too_high', a => 'old', value => 31}], "validation should work with deprecated";
}

{
	my $c  = create_engine();
	$c->define(sub {
		validation option('myoption'), message('too_high', "%option a% should be less than 30"), sub { $_ < 30 };
		command 'mycommand' => sub { validate(optional('myoption')), ok !valid('myoption'); };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31);
	cmp_deeply $res->{error_texts}, [q{"--myoption" should be less than 30}], "validation should work with option inline";
	cmp_deeply $res->{errors}, [{format => 'too_high', a => 'myoption', value => 31}], "validation should work with option inline";
}

{
	my $c  = create_engine(override_validations => { myoption => undef });
	$c->define(sub {
		validation option('myoption'), message('too_high', "%option a% should be less than 30"), sub { $_ < 30 };
		command 'mycommand' => sub { validate(optional('myoption')), ok valid('myoption'); };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31);
	ok !defined($res->{errors} || $res->{error_texts});
}

{
	my $c  = create_engine();
	$c->define(sub {
		ok ! defined eval { validation 'myoption', message('too_high', "%option a% should be less than 30"), sub { $_ < 30 }; 1; },
			"validation should die if option undeclared"
	});
}

{
	my $c  = create_engine();
	$c->define(sub {
		validation option('myoption'), message('too_high', "%option a% should be less than 30"), stop => 1, sub { $_ < 30 };
		validation 'myoption', message('way_too_high', "%option a% should be less than 100 for sure"), sub { $_ < 100 };
		command 'mycommand' => sub { validate optional('myoption') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 200);

	cmp_deeply $res->{error_texts}, [q{"--myoption" should be less than 30}], "should not perform two validations";
	cmp_deeply $res->{errors}, [{format => 'too_high', a => 'myoption', value => 200}], "should not perform two validations";
}

{
	my $c  = create_engine();
	$c->define(sub {
		validation option('myoption'), message('too_high', "%option a% should be less than 30"), stop => 0, sub { $_ < 30 };
		validation 'myoption', message('way_too_high', "%option a% should be less than 100 for sure"), sub { $_ < 100 };
		command 'mycommand' => sub { validate optional('myoption') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 200);

	cmp_deeply $res->{error_texts}, [q{"--myoption" should be less than 30}, q{"--myoption" should be less than 100 for sure}],
		"should perform two validations";
	cmp_deeply $res->{errors}, [{format => 'too_high', a => 'myoption', value => 200},
		{format => 'way_too_high', a => 'myoption', value => 200}], "should perform two validations";
}

{
	my $c  = create_engine();
	$c->define(sub {
		validation option('myoption'), message('way_too_high', "%option a% should be less than 100 for sure"), sub { $_ < 100 };
		validation 'myoption', message('too_high', "%option a% should be less than 30"), sub { $_ < 30 };
		command 'mycommand' => sub { validate optional('myoption') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 42);

	cmp_deeply $res->{error_texts}, [q{"--myoption" should be less than 30}], "should perform 2nd validation";
	cmp_deeply $res->{errors}, [{format => 'too_high', a => 'myoption', value => 42}], "should perform 2nd validations";
}


# mandatory

{
	my $c  = create_engine();
	$c->define(sub {
		message 'mandatory', "Please specify %option a%";
		options('myoption', 'myoption2');
		command 'mycommand' => sub { mandatory('myoption'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	cmp_deeply $res->{error_texts}, [q{Please specify "--myoption"}], "mandatory should work";
	cmp_deeply $res->{errors}, [{format => 'mandatory', a => 'myoption'}], "mandatory should work";
}

{
	my $c  = create_engine();
	$c->define(sub {
		message 'mandatory', "Please specify %option a%";
		options('myoption', 'myoption2', 'myoption3');
		command 'mycommand' => sub { mandatory('myoption', 'myoption3'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	cmp_deeply $res->{error_texts}, [q{Please specify "--myoption"}, q{Please specify "--myoption3"}], "should perform first mandatory check out of two";
	cmp_deeply $res->{errors}, [{format => 'mandatory', a => 'myoption'}, {format => 'mandatory', a => 'myoption3'}], "should perform first mandatory check out of two";
}

{
	my $c  = create_engine();
	$c->define(sub {
		message 'mandatory', "Please specify %option a%";
		options('myoption', 'myoption2', 'myoption3');
		command 'mycommand' => sub { mandatory(optional('myoption'), 'myoption3'), optional 'myoption2' };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	cmp_deeply $res->{error_texts}, [q{Please specify "--myoption3"}], "mandatory should work if inner optional() exists";
	cmp_deeply $res->{errors}, [{format => 'mandatory', a => 'myoption3'}], "mandatory should work if inner optional() exists";
}

{
	my $c  = create_engine();
	$c->define(sub {
		message 'mandatory', "Please specify %option a%";
		options('myoption', 'myoption2', 'myoption3');
		command 'mycommand' => sub { mandatory(mandatory('myoption'), 'myoption3'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	cmp_deeply $res->{error_texts}, [q{Please specify "--myoption"}, q{Please specify "--myoption3"}], "nested mandatoy should work";
	cmp_deeply $res->{errors}, [{format => 'mandatory', a => 'myoption'}, {format => 'mandatory', a => 'myoption3'}], "nested mandatoy should work";
}

{
	my $c  = create_engine();
	$c->define(sub {
		message 'mandatory', "Please specify %option a%";
		option 'myoption', default => 42;
		option 'myoption2';
		command 'mycommand' => sub { mandatory('myoption', 'myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{options}, { myoption => 42, myoption2 => 31}, "mandatory should work with default values";
}

# optional

{
	my $c  = create_engine();
	$c->define(sub {
		options('myoption', 'myoption2');
		command 'mycommand' => sub { optional('myoption'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	ok ! defined $res->{errors}, "optional should work";
	cmp_deeply $res->{options}, { myoption2 => 31}, "optional should work right when option is missing";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option ('myoption');
		option 'myoption2', default => 42;
		command 'mycommand' => sub { optional('myoption'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31);
	ok ! defined $res->{errors}, "optional should work";
	cmp_deeply $res->{options}, { myoption => 31, myoption2 => 42}, "optional should work with default values";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options('myoption', 'myoption2', 'myoption3');
		command 'mycommand' => sub { optional('myoption', 'myoption3'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	ok !defined $res->{errors}, 'should perform two optional checks';
}

{
	my $c  = create_engine();
	$c->define(sub {
		message 'mandatory', "Please specify %option a%";
		options('myoption', 'myoption2', 'myoption3');
		command 'mycommand' => sub { optional(mandatory('myoption'), 'myoption3'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	cmp_deeply $res->{error_texts}, [q{Please specify "--myoption"}], "optional should work right if inner mandatory() exists";
	cmp_deeply $res->{errors}, [{format => 'mandatory', a => 'myoption'}], "optional should work right if inner mandatory() exists";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options('myoption', 'myoption2', 'myoption3');
		command 'mycommand' => sub { optional(optional('myoption'), 'myoption3'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	ok ! defined $res->{errors}, 'nested optional should work';
}

# deprecated

{
	my $c  = create_engine();
	$c->define(sub {
		options('myoption', 'myoption2');
		command 'mycommand' => sub { optional('myoption'), deprecated('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-myoption2', 31);
	ok ! defined $res->{errors}, "optional should work";
	cmp_deeply $res->{warnings}, [{format => 'option_deprecated_for_command', a => 'myoption2'}];
	cmp_deeply $res->{options}, { }, "deprecated should work";
}


{
	my $c  = create_engine();
	$c->define(sub {
		option 'myoption';
		option 'myoption2', alias => 'old';
		command 'mycommand' => sub { optional('myoption'), deprecated('myoption2') };
	});
	my $res = $c->parse_options('mycommand', '-old', 31);
	ok ! defined $res->{errors}, "optional should work";
	cmp_deeply $res->{warnings}, [{format => 'option_deprecated_for_command', a => 'old'}];
	cmp_deeply $res->{options}, { }, "deprecated should work with alias";
}


# option

{
	my $c  = create_engine();
	$c->define(sub {
		option 'myoption';
		command 'mycommand' => sub { optional('myoption') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31);
	ok ! defined $res->{errors}, "option should work - no errors";
	ok ! defined $res->{error_texts}, "option should work - no errors";
	ok ! defined $res->{warnings}, "option should work - no warnings";
	ok ! defined $res->{warning_texts}, "option should work - no warnings";
	is $res->{command}, 'mycommand', "option should work - right command";
	cmp_deeply($res->{options}, { myoption => 31 }, "option should work should work");
}

# positional

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		command 'mycommand' => sub { optional('myoption') };
	});
	my @my_args = ('mycommand', 'zyx');
	my $res = $c->parse_options(@my_args);
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "positional should work";
	cmp_deeply($res->{options}, { myoption => 'zyx' }, "positional should work");
	cmp_deeply \@my_args, ['mycommand', 'zyx'], "should not alter args";
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		command 'mycommand' => sub { optional('myoption') };
	});
	my @my_args = ('mycommand', '-myoption', 'def');
	my $res = do {
		local $SIG{__WARN__} = 'DEFAULT';
		$c->parse_options(@my_args);
	};

	cmp_deeply $res->{error_texts}, ['Error parsing options'],
		"should not work if option with same name supplied as normal option";
	cmp_deeply $res->{errors}, [{ format => "getopts_error"}],
		"should not work if option with same name supplied as normal option";
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		positional 'myoption2';
		command 'mycommand' => sub { optional('myoption'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', 'zyx', 'abc');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "positional should work with two args";
	cmp_deeply($res->{options}, { myoption => 'zyx', 'myoption2' => 'abc' }, "positional should work with two args");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		positional 'myoption2';
		command 'mycommand' => sub { optional('myoption2'), optional('myoption') };
	});
	my $res = $c->parse_options('mycommand', 'zyx', 'abc');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { myoption2 => 'zyx', 'myoption' => 'abc' }, "order of args should be defined");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		command 'mycommand' => sub { mandatory('myoption') };
	});
	my $res = $c->parse_options('mycommand', 'zyx');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myoption' => 'zyx' }, "should work with mandatory");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		positional 'myoption2';
		command 'mycommand' => sub { mandatory('myoption'), mandatory('myoption2') };
	});
	my $res = $c->parse_options('mycommand', 'zyx', 'abc');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myoption' => 'zyx', 'myoption2' => 'abc' }, "should work with two mandatory");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		positional 'myoption2';
		command 'mycommand' => sub { mandatory('myoption'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', 'zyx', 'abc');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myoption' => 'zyx', 'myoption2' => 'abc' }, "should work with mandatory and optional");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		positional 'myoption2';
		command 'mycommand' => sub { mandatory('myoption'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', 'zyx');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myoption' => 'zyx'}, "should work with mandatory and optional when optional option is missing");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		command 'mycommand' => sub { optional('myoption') };
	});
	my $res = $c->parse_options('mycommand');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { }, "should work with optional when optional option is missing");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption', default => 42;
		command 'mycommand' => sub { optional('myoption') };
	});
	my $res = $c->parse_options('mycommand');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { myoption => 42 },
		"should work with optional when optional option is missing and have a default value");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		positional 'myoption2', default => 42;
		command 'mycommand' => sub { mandatory('myoption'), optional('myoption2') };
	});
	my $res = $c->parse_options('mycommand', 'zyx');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myoption' => 'zyx', myoption2 => 42},
		"should work with mandatory and optional when optional option is missing and have default value");
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		command 'mycommand' => sub { mandatory('myoption') };
	});
	my $res = $c->parse_options('mycommand');
	cmp_deeply $res->{error_texts}, ['Positional argument #1 (myoption) is mandatory'], "mandatory positional arg should work when missing";
	cmp_deeply $res->{errors}, [{ format => "positional_mandatory", a => 'myoption', n => 1}], "mandatory positional arg should work when missing";
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		positional 'myoption2';
		command 'mycommand' => sub { mandatory('myoption', 'myoption2') };
	});
	my $res = $c->parse_options('mycommand', 'z');
	cmp_deeply $res->{error_texts}, ['Positional argument #2 (myoption2) is mandatory'], "mandatory positional arg should work when missing";
	cmp_deeply $res->{errors}, [{ format => "positional_mandatory", a => 'myoption2', n => 2}], "mandatory positional arg should work when missing";
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		command 'mycommand' => sub { mandatory('myoption') };
	});
	my $res = $c->parse_options('mycommand', 'xx', 'zz');
	cmp_deeply $res->{error_texts}, ['Unexpected argument in command line: zz'], "should catch unexpected arguments";
	cmp_deeply $res->{errors}, [{ format => "unexpected_argument", a => 'zz'}], "should catch unexpected arguments";
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'myoption';
		command 'mycommand' => sub { mandatory('myoption') };
	});
	my $res = $c->parse_options('mycommand', 'xx', "\xA0");
	cmp_deeply $res->{error_texts}, ['Invalid UTF-8 character in command line'], "should catch broken utf-8";
	cmp_deeply $res->{errors}, [{ format => 'options_encoding_error', encoding => 'UTF-8' }], "should catch broken utf-8";
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'o1';
		positional 'o2';
		command 'mycommand' => sub { optional('o1'), mandatory('o2') };
	});
	ok ! defined eval { $c->parse_options('mycommand'); 1 }, "mandatory can't go after optional";
	ok $@ =~ /mandatory positional argument goes after optional one/i;
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'o1';
		positional 'o2';
		positional 'o3';
		command 'mycommand' => sub { optional('o1'), optional('o2'), mandatory('o3') };
	});
	ok ! defined eval { $c->parse_options('mycommand'); 1 }, "mandatory can't go after two optional";
	ok $@ =~ /mandatory positional argument goes after optional one/i;
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'p';
		option 'o';
		command 'mycommand' => sub { optional('o'), mandatory('p') };
	});
	my $res = $c->parse_options('mycommand', 'xyz', '-o', '42');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{options}, { o => '42', p => 'xyz' }, "should work together with options";
}

{
	my $c  = create_engine();
	$c->define(sub {
		positional 'o1';
		command 'mycommand' => sub { optional('o1')};
	});

	my $res = $c->parse_options('mycommand', encode("UTF-8", 'тест'));
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{options}, { o1 => 'тест' }, "positional args should work with UTF-8";
}


# option default

{
	my $c  = create_engine();
	$c->define(sub {
		option 'myoption';
		option 'myoption2', default => 42;
		command 'mycommand' => sub { optional('myoption') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31);
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "default option should work - right command";
	cmp_deeply($res->{options}, { myoption => 31 },
		"option with default values should work - default values should not appear in data if not requested");
}


{
	my $c  = create_engine();
	$c->define(sub {
		option 'myoption';
		ok ! defined eval { option 'myoption'; 1 }, "option should not work if specified twice";
	});
}

# options

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { optional('o1', 'o2') };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined $res->{errors};
	ok ! defined $res->{error_texts};
	ok ! defined $res->{warnings};
	ok ! defined $res->{warning_texts};
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { o1 => '11', o2 => '21' }, "options should work with two commands");
}


{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1';
		command 'mycommand' => sub { optional('o1') };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11');
	ok ! defined $res->{errors};
	ok ! defined $res->{error_texts};
	ok ! defined $res->{warnings};
	ok ! defined $res->{warning_texts};
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { o1 => '11' }, "options should work with one command");
}

# option alias
{
	my $c  = create_engine();
	$c->define(sub {
		message 'already_specified_in_alias';
		option 'o1', alias => 'old';
		command 'mycommand', sub { optional('o1') };
	});
	my $res = $c->parse_options('mycommand', '-old', '11');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply($res->{options}, { o1 => '11' }, "alias should work");
	cmp_deeply($c->{options}->{o1},
		{ value => '11', name => 'o1', seen => 1, alias => ['old'], source => 'option', original_option => 'old', is_alias => 1  },
		"alias should work");
}

for (['-old', '11', '-o1', '42'], ['-o1', '42', '-old', '11']) {
	my $c  = create_engine();
	$c->define(sub {
		message 'already_specified_in_alias', "both options %option a% and %option b% are specified. however they are aliases";
		option 'o1', alias => 'old';
		command 'mycommand', sub { optional('o1') };
	});
	cmp_deeply [sort qw/old o1/], [qw/o1 old/];
	my $res = $c->parse_options('mycommand', @$_);
	ok ! defined ($res->{warnings}||$res->{warning_texts});
	ok $res->{errors} && $res->{error_texts};
	ok @{$res->{error_texts}} == 1;
	cmp_deeply $res->{error_texts}, ['both options "--o1" and "--old" are specified. however they are aliases'], "should not be able to specify option twice using alias";
	cmp_deeply $res->{errors}, [{format => 'already_specified_in_alias', a => 'o1', b => 'old'}], "should not be able to specify option twice using alias";
}

for (['-o0', '11', '-o1', '42'], ['-o1', '42', '-o0', '11']) {
	my $c  = create_engine();
	$c->define(sub {
		message 'already_specified_in_alias', "both options %option a% and %option b% are specified. however they are aliases";
		option 'o1', alias => 'o0';
		command 'mycommand', sub { optional('o1') };
	});
	cmp_deeply [sort qw/o0 o1/], [qw/o0 o1/];
	my $res = $c->parse_options('mycommand', @$_);
	ok ! defined ($res->{warnings}||$res->{warning_texts});
	ok $res->{errors} && $res->{error_texts};
	ok @{$res->{error_texts}} == 1;
	cmp_deeply $res->{error_texts}, ['both options "--o0" and "--o1" are specified. however they are aliases'],
		"should not be able to specify option twice using alias";
	cmp_deeply $res->{errors}, [{format => 'already_specified_in_alias', a => 'o0', b => 'o1'}],
		"should not be able to specify option twice using alias";
}

for (['-o0', '11', '-o1', '42'], ['-o1', '42', '-o0', '11']) {
	my $c  = create_engine();
	$c->define(sub {
		message 'already_specified_in_alias', "both options %option a% and %option b% are specified. however they are aliases";
		option 'x', alias => ['o1', 'o0'];
		command 'mycommand', sub { optional('x') };
	});
	cmp_deeply [sort qw/o0 o1/], [qw/o0 o1/];
	my $res = $c->parse_options('mycommand', @$_);
	ok ! defined ($res->{warnings}||$res->{warning_texts});
	ok $res->{errors} && $res->{error_texts};
	ok @{$res->{error_texts}} == 1;
	cmp_deeply $res->{error_texts}, ['both options "--o0" and "--o1" are specified. however they are aliases'],
		"should not be able to specify option twice using two aliases";
	cmp_deeply $res->{errors}, [{format => 'already_specified_in_alias', a => 'o0', b => 'o1'}],
		"should not be able to specify option twice using two aliases";
}

for (['-o0', '11', '-o1', '42'], ['-o1', '42', '-o0', '11']) {
	my $c  = create_engine();
	$c->define(sub {
		message 'deprecated_option', "option %option option% is deprecated";
		message 'already_specified_in_alias', "both options %option a% and %option b% are specified. however they are aliases";
		option 'x', deprecated => ['o1', 'o0'];
		command 'mycommand', sub { optional('x') };
	});
	cmp_deeply [sort qw/o0 o1/], [qw/o0 o1/];
	my $res = $c->parse_options('mycommand', @$_);
	ok $res->{errors} && $res->{error_texts} && $res->{warnings} && $res->{warning_texts};
	ok @{$res->{error_texts}} == 1;
	cmp_deeply $res->{error_texts}, ['both options "--o0" and "--o1" are specified. however they are aliases'],
		"should not be able to specify option twice using two deprecations";
	cmp_deeply $res->{errors}, [{format => 'already_specified_in_alias', a => 'o0', b => 'o1'}],
		"should not be able to specify option twice using two deprecations";
}

for (['-o0', '11', '-o1', '42'], ['-o1', '42', '-o0', '11']) {
	my $c  = create_engine();
	$c->define(sub {
		message 'deprecated_option', "option %option option% is deprecated";
		message 'already_specified_in_alias', "both options %option a% and %option b% are specified. however they are aliases";
		option 'x', deprecated => 'o1', alias => 'o0';
		command 'mycommand', sub { optional('x') };
	});
	cmp_deeply [sort qw/o0 o1/], [qw/o0 o1/];
	my $res = $c->parse_options('mycommand', @$_);
	ok $res->{errors} && $res->{error_texts} && $res->{warnings} && $res->{warning_texts};
	ok @{$res->{error_texts}} == 1;
	cmp_deeply $res->{error_texts}, ['both options "--o0" and "--o1" are specified. however they are aliases'],
		"should not be able to specify option twice using deprecation and alias";
	cmp_deeply $res->{errors}, [{format => 'already_specified_in_alias', a => 'o0', b => 'o1'}],
		"should not be able to specify option twice using deprecation and alias";
}

# option deprecated
{
	my $c  = create_engine();
	$c->define(sub {
		message 'deprecated_option', "option %option option% is deprecated";
		message 'already_specified_in_alias';
		option 'o1', deprecated => 'old';
		command 'mycommand', sub { optional('o1') };
	});
	my $res = $c->parse_options('mycommand', '-old', '11');
	ok ! defined ($res->{errors}||$res->{error_texts});
	ok $res->{warnings} && $res->{warning_texts};
	cmp_deeply $res->{warning_texts}, ['option "--old" is deprecated'], "deprecated options should work";
	cmp_deeply $res->{warnings}, [{format => 'deprecated_option', option => 'old', main => 'o1'}], "deprecated options should work";
	cmp_deeply($res->{options}, { o1 => '11' }, "deprecated options should work");
	cmp_deeply($c->{options}->{o1},
		{ value => '11', name => 'o1', seen => 1, deprecated => ['old'], source => 'option', original_option => 'old', is_alias => 1 },
		"deprecated options should work");
}


# scope

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { scope ('myscope', optional('o1')), optional('o2') };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myscope' => { o1 => '11'}, o2 => '21' }, "scope should work");
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { scope ('myscope', optional('o1'), optional('o2')) };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myscope' => { o1 => '11', o2 => '21'} }, "scope should work with two options");
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { scope ('myscope', scope('inner', optional('o1'))), optional('o2') };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myscope' => { 'inner' => { o1 => '11'}}, o2 => '21' }, "nested scope should work");
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { scope ('myscope', scope('inner', optional('o1'), optional('o2'))) };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myscope' => { 'inner' => { o1 => '11',  o2 => '21'}} }, "nested scope should work with two options");
}

# custom

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o3';
		command 'mycommand' => sub { scope ('myscope', optional('o3'), custom('o1', '42')), custom('o2', '41') };
	});
	my $res = $c->parse_options('mycommand', '-o3', '11');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand';
	cmp_deeply($res->{options}, { 'myscope' => { o1 => '42',  o3 => '11'}, o2 => 41 }, "custom should work");
}


# error, message, present, value

{
	my $c  = create_engine();
	$c->define(sub {
		message 'mutual', "%option a% and %option b% are mutual exclusive";
		options 'o1', 'o2';
		command 'mycommand' => sub {
			optional('o1'), mandatory('o2');
			if (present('o1') && present('o2')) {
				error('mutual', a => 'o1', b => 'o2');
			}
		};
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined $res->{warnings}||$res->{warning_texts};
	cmp_deeply $res->{error_texts}, [q{"--o1" and "--o2" are mutual exclusive}], "error should work";
	cmp_deeply $res->{errors}, [{format => 'mutual', a => 'o1', b => 'o2'}], "error should work";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub {
			optional('o1'), mandatory('o2');
			if (present('o1') && present('o2')) {
				error('mymessage');
			}
		};
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined $res->{warnings}||$res->{warning_texts};
	cmp_deeply $res->{error_texts}, [q{mymessage}], "error should work with undeclared message";
	cmp_deeply $res->{errors}, ['mymessage'], "error should work with undeclared message";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		message 'mymessage', 'some text';
		command 'mycommand' => sub {
			optional('o1'), mandatory('o2');
			if (present('o1') && present('o2')) {
				error('mymessage');
			}
		};
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined $res->{warnings}||$res->{warning_texts};
	cmp_deeply $res->{error_texts}, [q{some text}], "error should work with declared message without variables";
	cmp_deeply $res->{errors}, [{ format => 'mymessage'}], "error should work with declared message without variables";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub {
			optional('o1'), mandatory('o2');
			if (present('o1') && present('o2')) {
				error('mymessage');
			}
		};
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined $res->{warnings}||$res->{warning_texts};
	cmp_deeply $res->{error_texts}, [q{mymessage}], "error should work with declared message without variables";
	cmp_deeply $res->{errors}, ['mymessage'], "error should work with declared message without variables";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub {
			optional('o1'), mandatory('o2');
			if (value('o1') == 11 and value('o2') == 21) {
				error('mymessage');
			}
		};
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok ! defined $res->{warnings}||$res->{warning_texts};
	cmp_deeply $res->{error_texts}, [q{mymessage}], "error should work with declared message without variables";
	cmp_deeply $res->{errors}, ['mymessage'], "error should work with declared message without variables";
}

# command

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1';
		command 'mycommand', alias => 'commandofmine', sub { optional 'o1' };
	});
	my $res = $c->parse_options('commandofmine', '-o1', '11');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', 'alias should work';
}

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1';
		command 'mycommand', alias => ['c1', 'c2'], sub { optional 'o1' };
	});
	my $res = $c->parse_options('c2', '-o1', '11');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', 'multiple aliases should work';
}

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1';
		command 'mycommand', deprecated => 'commandofmine', sub { optional 'o1' };
	});
	my $res = $c->parse_options('commandofmine', '-o1', '11');
	ok ! defined ($res->{errors}||$res->{error_texts});
	is $res->{command}, 'mycommand', 'alias should work';
	ok $res->{warnings};
	ok $res->{warning_texts};
	cmp_deeply $res->{warning_texts}, ['Command "commandofmine" is deprecated'], "deprecated commands should work";
	cmp_deeply $res->{warnings}, [{ format => 'deprecated_command', command => 'commandofmine'} ], "deprecated commands should work";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1';
		message 'deprecated_command', "command %command% is deprecated";
		command 'mycommand', deprecated => 'commandofmine', sub { optional 'o1' };
	});
	my $res = $c->parse_options('commandofmine', '-o1', '11');
	ok ! defined ($res->{errors}||$res->{error_texts});
	is $res->{command}, 'mycommand', 'alias should work';
	ok $res->{warnings};
	ok $res->{warning_texts};
	cmp_deeply $res->{warning_texts}, ["command commandofmine is deprecated"], "deprecated commands should work";
	cmp_deeply $res->{warnings}, [{ format => 'deprecated_command', command => 'commandofmine'} ], "deprecated commands should work";
}

# parse options

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { optional('o1') };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-o2', '21');
	ok defined $res->{errors};
	ok defined $res->{error_texts};
	ok ! defined $res->{warnings};
	ok ! defined $res->{warning_texts};
	ok ! defined $res->{command}, "command should be undefined in case of errors";
	cmp_deeply $res->{error_texts}, ['Unexpected option "--o2"'], "should catch unexpected options";
	cmp_deeply $res->{errors}, [{ format => 'unexpected_option', option => 'o2' }], "should catch unexpected options";
	ok ! defined $App::MtAws::ConfigEngine::context, "context should be always localized";
}


{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1';
		option 'o2', alias => 'old';
		command 'mycommand' => sub { optional('o1') };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-old', '21');
	ok defined $res->{errors};
	ok defined $res->{error_texts};
	ok ! defined $res->{warnings};
	ok ! defined $res->{warning_texts};
	ok ! defined $res->{command}, "command should be undefined in case of errors";
	cmp_deeply $res->{error_texts}, ['Unexpected option "--old"'], "should catch unexpected options when alias";
	cmp_deeply $res->{errors}, [{ format => 'unexpected_option', option => 'old' }], "should catch unexpected options when alias";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1';
		option 'o2', deprecated => 'old';
		command 'mycommand' => sub { optional('o1') };
	});
	my $res = $c->parse_options('mycommand', '-o1', '11', '-old', '21');
	ok defined $res->{errors};
	ok defined $res->{error_texts};
	ok defined $res->{warnings};
	ok defined $res->{warning_texts};
	ok ! defined $res->{command}, "command should be undefined in case of errors";
	cmp_deeply $res->{error_texts}, ['Unexpected option "--old"'], "should catch unexpected options when alias";
	cmp_deeply $res->{errors}, [{ format => 'unexpected_option', option => 'old' }], "should catch unexpected options when alias";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { optional('o1') };
	});
	my $res = $c->parse_options('mycommand', '-o1', encode("UTF-8", 'тест'));
	ok !defined( $res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "command should be defined";
	cmp_deeply $res->{options}, { o1 => 'тест'}, "Should decode UTF options";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { optional('o1') };
	});
	my $res = $c->parse_options('mycommand', '-o1', "\xA0");
	ok !defined( $res->{warnings}||$res->{warning_texts});
	ok ! defined $res->{command}, "command should be undefined";
	cmp_deeply $res->{error_texts}, ['Invalid UTF-8 character in command line'], "should catch broken utf-8";
	cmp_deeply $res->{errors}, [{ format => 'options_encoding_error', encoding => 'UTF-8' }], "should catch broken utf-8";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { optional('o1'), optional('o2') };
	});
	my $res = $c->parse_options('mycommand', '-o1', "\xA0", '-o2', "\xA1");
	ok !defined( $res->{warnings}||$res->{warning_texts});
	ok ! defined $res->{command}, "command should be undefined";
	cmp_deeply $res->{error_texts}, ['Invalid UTF-8 character in command line'], "should catch broken utf-8 just once";
	cmp_deeply $res->{errors}, [{ format => 'options_encoding_error', encoding => 'UTF-8' }], "should catch broken utf-8 just once";
}



{
	local *App::MtAws::ConfigEngine::read_config = sub { return { o1 => "\xA0", o2 => "\xA0"} };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		options 'o1', 'o2';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('o1'), optional('o2'), optional('config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c');
	ok !defined( $res->{warnings}||$res->{warning_texts});
	ok ! defined $res->{command}, "command should be undefined";
	cmp_deeply $res->{error_texts}, ['Invalid UTF-8 character in config file'], "should catch broken utf-8 in config just once";
	cmp_deeply $res->{errors}, [{ format => 'config_encoding_error', encoding => 'UTF-8' }], "should catch broken utf-8 in config just once";
}


{
	my $c  = create_engine();
	$c->define(sub {
		options 'o1', 'o2';
		command 'mycommand' => sub { optional('o1')};
	});
	my $res = $c->parse_options('mycommand', '-o1', "ok", '-o2', "\xA1");
	ok !defined( $res->{warnings}||$res->{warning_texts});
	ok ! defined $res->{command}, "command should be undefined";
	cmp_deeply $res->{error_texts}, ['Invalid UTF-8 character in command line'], "should catch broken utf-8 even if option is not used";
	cmp_deeply $res->{errors}, [{ format => 'options_encoding_error', encoding => 'UTF-8' }], "should catch broken utf-8 even if option is not used";
}

{
	my $c  = create_engine();
	$c->define(sub {
		command 'mycommand' => sub { };
	});
	my $res = $c->parse_options('mycommand');
	ok !defined( $res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "should work without options";
	cmp_deeply $res->{options}, {}, "should work without options";
}

{
	my $c  = create_engine();
	$c->define(sub {
		options 'myoption';
		command 'mycommand' => sub { optional('myoption')};
	});
	my $res = do {
		local $SIG{__WARN__} = 'DEFAULT';
		$c->parse_options('mycommand', '-MYoption', 123);
	};
	ok $res->{errors} && $res->{error_texts};
	cmp_deeply $res->{errors}, [{ format => 'getopts_error'}], "should not ignore options case";
}

# parse options - array options

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1', type => 's', list => 1;
		command 'mycommand' => sub { optional 'o1' };
	});
	my $res = $c->parse_options('mycommand', '-o1', 'a', '-o1', 'b');
	ok !defined($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{options}, { o1 => ['a', 'b']}, "array options should work";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1', alias => 'o2', type => 's', list => 1;
		command 'mycommand' => sub { optional 'o1' };
	});
	my $res = $c->parse_options('mycommand', '-o2', 'a', '-o2', 'b');
	ok !defined($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{options}, { o1 => ['a', 'b']}, "array options should work with aliases";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1', alias => 'o2', type => 's', list => 1;
		command 'mycommand' => sub { optional 'o1' };
	});
	my $res = $c->parse_options('mycommand', '-o2', 'a', '-o1', 'b');
	ok !defined($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{options}, { o1 => ['a', 'b']}, "array options should work when mixing aliases and options";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1', deprecated => 'o2', type => 's', list => 1;
		command 'mycommand' => sub { optional 'o1' };
	});
	my $res = $c->parse_options('mycommand', '-o2', 'a', '-o1', 'b');
	ok !defined($res->{errors}||$res->{error_texts});
	ok $res->{warnings} && $res->{warning_texts};
	cmp_deeply $res->{options}, { o1 => ['a', 'b']}, "array options should work when mixing deprecations and options";
}
{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1', deprecated => 'o2', type => 's', list => 1;
		command 'mycommand' => sub { optional 'o1' };
	});
	my $res = $c->parse_options('mycommand', '-o2', 'a', '-o2', 'b');
	ok !defined($res->{errors}||$res->{error_texts});
	ok $res->{warnings} && $res->{warning_texts};
	cmp_deeply $res->{options}, { o1 => ['a', 'b']}, "array options should work with deprecations";
}

# option lists

{
	my $c  = create_engine();
	$c->define(sub {
		option('include', type => 's', list => 1),
		option('exclude', list => 1),
		option('filter', type => 's', list => 1);
		command 'mycommand' => sub { optional qw/include exclude filter/ };
	});
	my $res = $c->parse_options('mycommand', qw/--include 1 --exclude 2 --filter 3 --filter 4 --include 5/);
	ok !defined($res->{errors}||$res->{error_texts}||$res->{warnings} && $res->{warning_texts});
	cmp_deeply $res->{options}, {
		include => [qw/1 5/],
		exclude => [qw/2/],
		filter => [qw/3 4/],
	}, "shared lists should work";
	cmp_deeply $res->{option_list}, [
		{ name => 'include', value => 1 },
		{ name => 'exclude', value => 2 },
		{ name => 'filter', value => 3 },
		{ name => 'filter', value => 4 },
		{ name => 'include', value => 5 },
	], "shared lists should work";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option('include', type => 's', list => 1),
		option('exclude', list => 1),
		option('filter', type => 's', list => 1);
		options('o1', 'o2');
		command 'mycommand' => sub {
			optional qw/o1 o2/;
			cmp_deeply [lists optional qw/include exclude filter/], [
				{ name => 'include', value => 1 },
				{ name => 'exclude', value => 2 },
				{ name => 'filter', value => 3 },
				{ name => 'filter', value => 4 },
				{ name => 'include', value => 5 },
			], 'lists() should work';
			cmp_deeply [lists('include')], [
				{ name => 'include', value => 1 },
				{ name => 'include', value => 5 },
			], 'lists() should work';
		};
	});
	my $res = $c->parse_options('mycommand', qw/--include 1 --exclude 2 --o2 2 --filter 3 --filter 4 --include 5 --o1 1/);
	ok !defined($res->{errors}||$res->{error_texts}||$res->{warnings} && $res->{warning_texts});
	cmp_deeply $res->{options}, {
		include => [qw/1 5/],
		exclude => [qw/2/],
		filter => [qw/3 4/],
		o1 => 1,
		o2 => 2,
	}, "shared lists should work";
	cmp_deeply $res->{option_list}, [
		{ name => 'include', value => 1 },
		{ name => 'exclude', value => 2 },
		{ name => 'filter', value => 3 },
		{ name => 'filter', value => 4 },
		{ name => 'include', value => 5 },
	], "option_list should contain only lists arguments";
}


# parse options - system messages

{
	my $c  = create_engine();
	$c->define(sub {
		command 'mycommand' => sub { };
	});
	my $res = $c->parse_options();
	ok $res->{errors} && $res->{error_texts};
	ok !defined( $res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{error_texts}, ['No command specified'], "should catch no command";
	cmp_deeply $res->{errors}, [{ format => 'no_command' }], "should catch no command";
}


{
	my $c  = create_engine();
	$c->define(sub {
		message 'no_command', "Command missing";
		command 'mycommand' => sub { };
	});
	my $res = $c->parse_options();
	ok $res->{errors} && $res->{error_texts};
	ok !defined( $res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{error_texts}, ['Command missing'], "should catch no command with custom message";
	cmp_deeply $res->{errors}, [{ format => 'no_command' }], "should catch no command with custom message";
}

{
	my $c  = create_engine();
	$c->define(sub {
		command 'mycommand' => sub { };
	});
	my $res = $c->parse_options('zz');
	ok $res->{errors} && $res->{error_texts};
	ok !defined( $res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{error_texts}, ['Unknown command "zz"'], "should catch unknown command";
	cmp_deeply $res->{errors}, [{ format => 'unknown_command', a => 'zz' }], "should catch unknown command";
}

{
	my $c  = create_engine();
	$c->define(sub {
		message 'unknown_command', "Command typo [%a%]";
		command 'mycommand' => sub { };
	});
	my $res = $c->parse_options('zz');
	ok $res->{errors} && $res->{error_texts};
	ok !defined( $res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{error_texts}, ['Command typo [zz]'], "should catch unknown command with custom message";
	cmp_deeply $res->{errors}, [{ format => 'unknown_command', a => 'zz' }], "should catch unknown command with custom message";
}

{
	my $c  = create_engine();
	$c->define(sub {
		command 'mycommand' => sub { };
	});
	my $res = do {
		local $SIG{__WARN__} = 'DEFAULT';
		$c->parse_options('mycommand', '--f--');
	};
	ok $res->{errors} && $res->{error_texts};
	ok !defined( $res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{error_texts}, ['Error parsing options'], "should catch error parsing options";
	cmp_deeply $res->{errors}, [{ format => 'getopts_error' }], "should catch error parsing options";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1', type => 'i';
		command 'mycommand' => sub { mandatory('o1') };
	});
	my $res = do {
		local $SIG{__WARN__} = 'DEFAULT';
		$c->parse_options('mycommand', '--o1=3.3');
	};
	ok $res->{errors} && $res->{error_texts};
	ok !defined( $res->{warnings}||$res->{warning_texts});
	cmp_deeply $res->{error_texts}, ['Error parsing options'], "should allow to define option types";
	cmp_deeply $res->{errors}, [{ format => 'getopts_error' }], "should allow to define option types";
}

{
	my $c  = create_engine();
	$c->define(sub {
		option 'o1', type => '';
		command 'mycommand' => sub { mandatory('o1') };
	});
	my $res = $c->parse_options('mycommand', '--o1');
	ok !defined( $res->{warnings}||$res->{warning_texts}||$res->{error_texts}||$res->{errors});
	cmp_deeply $res->{options}, { o1 => 1}, "should allow to define option types with empty type";
}

# config

{
	local *App::MtAws::ConfigEngine::read_config = sub { { fromconfig => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'fromconfig';
		option 'myoption';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('fromconfig', 'myoption', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31, '-config', 'c');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "config should work - right command";
	cmp_deeply($res->{options}, { myoption => 31, fromconfig => 42 , config => 'c'}, "config should work");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { 'from-dir' => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'dir', alias => 'from-dir';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('dir', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "config should work - right command";
	cmp_deeply($res->{options}, { dir => 42 , config => 'c'}, "config should work with aliases");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { 'from-dir' => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'dir', deprecated => 'from-dir';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('dir', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "config should work - right command";
	cmp_deeply($res->{options}, { dir => 42 , config => 'c'}, "config should work with depracations");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { fromconfig => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'myoption';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('myoption', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31, '-config', 'c');
	cmp_deeply $res->{error_texts}, ['Unknown option in config: "fromconfig"'], "should catch unknown option in config";
	cmp_deeply $res->{errors}, [{ format => 'unknown_config_option', option => 'fromconfig' }], "should catch unknown option in config";
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { include => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'include', list => 1;
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('include', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c');
	cmp_deeply $res->{error_texts}, ['"List" options (where order is important) like "include" cannot appear in config currently'],
		"should catch list options in config";
	cmp_deeply $res->{errors}, [{ format => 'list_options_in_config', option => 'include' }], "should catch list options in config";
}


{
	local *App::MtAws::ConfigEngine::read_config = sub { { fromconfig => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'fromconfig', default => 43;
		option 'myoption';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('fromconfig', 'myoption', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31, '-config', 'c');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply($res->{options}, { myoption => 31, fromconfig => 42 , config => 'c'}, "config should override default");
}

{
	my $fname = undef;
	local *App::MtAws::ConfigEngine::read_config = sub { (undef, $fname) = @_; { fromconfig => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'fromconfig', default => 43;
		option 'myoption';
		option 'config', default => 'cx', binary=>1;
		command 'mycommand' => sub { optional('fromconfig', 'myoption', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31);
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $fname, 'cx', "should read right config file";
	cmp_deeply($res->{options}, { myoption => 31, fromconfig => 42 , config => 'cx'},
		"config should work even if there is  default for config");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { fromconfig => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'fromconfig';
		option 'myoption';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('fromconfig', 'myoption', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31, '-config', 'c', '-fromconfig', 43);
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply($res->{options}, { myoption => 31, fromconfig => 43 , config => 'c'}, "command line should override config");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { fromconfig => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'fromconfig', default => 44;
		option 'myoption';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('fromconfig', 'myoption', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-myoption', 31, '-config', 'c', '-fromconfig', 43);
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	cmp_deeply($res->{options}, { myoption => 31, fromconfig => 43 , config => 'c'}, "command line should override config and default");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { fromconfig => 42 } };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'fromconfig', default => 44;
		option 'myoption';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('fromconfig', 'myoption') };
	});
	ok ! defined eval { $c->parse_options('mycommand', '-myoption', 31, '-config', 'c', '-fromconfig', 43); 1; };
	ok $@ =~ /must be seen/, "should catch when config option not seen";
}


{
	local *App::MtAws::ConfigEngine::read_config = sub { return; };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'fromconfig', default => 44;
		option 'myoption';
		option 'config', binary=>1;
		command 'mycommand' => sub { optional('fromconfig', 'myoption', 'config') };
	});
	ok ! defined eval { $c->parse_options('mycommand', '-myoption', 31, '-config', 'cx') };
}

# encodings

{
	my $c  = create_engine(CmdEncoding => 'encoding');
	$c->define(sub {
		option 'o1', default => 44;
		option 'encoding', binary => 1;
		command 'mycommand' => sub { optional('o1'), optional('encoding') };
	});
	my $res = $c->parse_options('mycommand', '-o1', encode('koi8-r', "тест"), '-encoding', 'koi8-r');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options}, { o1 => 'тест' , encoding => 'koi8-r'}, "cmd encoding should work");
}

{
	my $c  = create_engine(CmdEncoding => 'encoding');
	$c->define(sub {
		option 'o1', default => 44;
		option 'encoding', binary => 1;
		command 'mycommand' => sub { optional('o1'), optional('encoding') };
	});
	my $res = $c->parse_options('mycommand', '-o1', encode('utf-8', "тест"), '-encoding', 'utf-8');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options}, { o1 => 'тест' , encoding => 'utf-8'}, "cmd encoding should work with utf8");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { encoding => 'koi8-r' } };
	my $c  = create_engine(CmdEncoding => 'encoding', ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'config', binary=>1;
		option 'encoding', binary => 1;
		command 'mycommand' => sub { optional('o1'), optional('encoding', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-o1', encode('koi8-r', "тест"), '-config', 'c' );
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options}, { o1 => 'тест' , encoding => 'koi8-r', config => 'c'}, "cmd encoding should work when specified in config");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { encoding => 'cp1251' } };
	my $c  = create_engine(CmdEncoding => 'encoding', ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'config', binary=>1;
		option 'encoding', binary => 1;
		command 'mycommand' => sub { optional('o1'), optional('encoding', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-o1', encode('koi8-r', "тест"), '-config', 'c', '-encoding', 'koi8-r' );
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options}, { o1 => 'тест' , encoding => 'koi8-r', config => 'c'}, "cmd encoding should work when command line overrides");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { o1 => encode('koi8-r', "тест") } };
	my $c  = create_engine(ConfigEncoding => 'encoding', ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'config', binary=>1;
		option 'encoding', binary => 1;
		command 'mycommand' => sub { optional('o1'), optional('encoding', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c', '-encoding', 'koi8-r' );
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options}, { o1 => 'тест' , encoding => 'koi8-r', config => 'c'}, "cfg encoding should work");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { o1 => encode('utf-8', "тест") } };
	my $c  = create_engine(ConfigEncoding => 'encoding', ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'config', binary=>1;
		option 'encoding', binary => 1;
		command 'mycommand' => sub { optional('o1'), optional('encoding', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c', '-encoding', 'utf-8' );
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options}, { o1 => 'тест' , encoding => 'utf-8', config => 'c'}, "cfg encoding should work");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { o1 => encode('koi8-r', "тест"), encoding => 'koi8-r' } };
	my $c  = create_engine(ConfigEncoding => 'encoding', ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'config', binary=>1;
		option 'encoding', binary => 1;
		command 'mycommand' => sub { optional('o1'), optional('encoding', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options}, { o1 => 'тест' , encoding => 'koi8-r', config => 'c'}, "cfg encoding should work when specified in config");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { o1 => encode('koi8-r', "тест"), encoding => 'cp1251' } };
	my $c  = create_engine(ConfigEncoding => 'encoding', ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'config', binary=>1;
		option 'encoding', binary => 1;
		command 'mycommand' => sub { optional('o1'), optional('encoding', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c', '-encoding', 'koi8-r');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options}, { o1 => 'тест' , encoding => 'koi8-r', config => 'c'}, "cfg encoding should work when specified in config");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { o1 => encode('koi8-r', "тест"), 'cmd-encoding' => 'cp1251' } };
	my $c  = create_engine(ConfigEncoding => 'cfg-encoding', CmdEncoding => 'cmd-encoding', ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'o2';
		option 'config', binary=>1;
		option 'cfg-encoding', binary => 1;
		option 'cmd-encoding', binary => 1;
		command 'mycommand' => sub { optional('o1', 'o2'), optional('cmd-encoding', 'cfg-encoding', 'config') };
	});
	my $res = $c->parse_options('mycommand', '-config', 'c', '-cfg-encoding', 'koi8-r', '-o2', encode('cp1251', 'тест2'));
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options},
		{ o1 => 'тест' , o2 => 'тест2', 'cmd-encoding' => 'cp1251', 'cfg-encoding' => 'koi8-r', config => 'c'},
		"cfg and cmd encodings should work together");
}

{
	my $c  = create_engine(CmdEncoding => 'cmd-encoding');
	$c->define(sub {
		option 'o1', default => 44;
		option 'cmd-encoding';
		command 'mycommand' => sub { optional('o1', 'cmd-encoding') };
	});
	ok ! defined eval { $c->parse_options('mycommand', '-o1', '1'); 1 };
	ok $@ =~ /declared as binary/i, "should catch cmd encoding binary";
}

{
	my $c  = create_engine(ConfigEncoding => 'cmd-encoding');
	$c->define(sub {
		option 'o1', default => 44;
		option 'cmd-encoding';
		command 'mycommand' => sub { optional('o1', 'cmd-encoding') };
	});
	ok ! defined eval { $c->parse_options('mycommand', '-o1', '1'); 1 };
	ok $@ =~ /declared as binary/i, "should catch cfg encoding binary";
}

{
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'config';
		command 'mycommand' => sub { optional('o1', 'config') };
	});
	ok ! defined eval { $c->parse_options('mycommand', '-o1', '1'); 1 };
	ok $@ =~ /ConfigOption.*declared as binary/i, "should catch cfg encoding binary";
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { return {} };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'o1', default => 44;
		option 'config', binary => 1;
		command 'mycommand' => sub { optional('o1', 'config') };
	});
	my $res =  $c->parse_options('mycommand', '-o1', '1', '-config', encode('koi8-r', 'тест'));
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options},
		{ o1 => 1, config => encode('koi8-r', 'тест')},
		"should not decode binary command line options");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { return { o1 => encode('koi8-r', 'тест1'), o2 => encode('utf-8', 'тест2')} };
	my $c  = create_engine(ConfigOption => 'config');
	$c->define(sub {
		option 'o1', binary => 1;
		option 'o2';
		option 'config', binary => 1;
		command 'mycommand' => sub { optional('o1', 'o2', 'config') };
	});
	my $res =  $c->parse_options('mycommand', '-config', 'c');
	ok ! defined ($res->{errors}||$res->{error_texts}||$res->{warnings}||$res->{warning_texts});
	is $res->{command}, 'mycommand', "encodings - right command";
	cmp_deeply($res->{options},
		{ o1 => 1, config => 'c', o1 => encode('koi8-r', 'тест1'), o2 => 'тест2'},
		"should not decode binary command line options in config");
}



sub create_engine
{
	App::MtAws::ConfigEngine->new(@_);
}

1;
