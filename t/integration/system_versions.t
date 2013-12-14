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
use Test::More tests => 18;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils;
use App::MtAws;

warning_fatal();

my @dynamic_modules = map { my $a = $_;  $a =~ s!::!/!g; $a; } qw/
	Command::Sync
	Command::Retrieve
	Command::CheckLocalHash
	Command::DownloadInventory
/;


ok eval { App::MtAws::check_module_versions(); 1 };

{
	use App::MtAws::Filter;
	local *App::MtAws::Filter::VERSION = sub { '0.55' };
	ok ! defined eval { App::MtAws::check_module_versions(); 1 };
	ok $@ =~ /FATAL: wrong version of App::MtAws::Filter, expected $App::MtAws::VERSION, found 0.55/, "should work when version is wrong";
}

{
	use App::MtAws::Filter;
	local *App::MtAws::Filter::VERSION = sub { '999.999' };
	ok ! defined eval { App::MtAws::check_module_versions(); 1 };
	ok $@ =~ /FATAL: wrong version of App::MtAws::Filter, expected $App::MtAws::VERSION, found 999.999/, "should work when version is too hight";
}

{
	use App::MtAws::Filter;
	local *App::MtAws::Filter::VERSION = sub { };
	ok ! defined eval { App::MtAws::check_module_versions(); 1 };
	ok $@ =~ /FATAL: wrong version of App::MtAws::Filter, expected $App::MtAws::VERSION, found undef/, "should work when version is undef";
}

{
	use App::MtAws;
	ok ! $INC{$_}, "module $_ is not loaded as dynamic" for map { "App/MtAws/${_}.pm" } @dynamic_modules;
}

{
	App::MtAws::check_all_dynamic_modules();
	ok $INC{$_}, "module $_ is loaded as dynamic" for map { "App/MtAws/${_}.pm" } @dynamic_modules;
}

{
	ok defined eval { App::MtAws::print_system_modules_version(); 1 };
}


##
## not related to versions test.
##

{
	my $i = 0;
	while () {
		last if ++$i == 3;
	}
	is $i, 3, "while() should produce infinite loop";
}

{
	my $i = 0;
	alarm 3;
	++$i while ();
	alarm 0;
	is $i, 0, "while() without block should not produce infinite loop";
}

1;
