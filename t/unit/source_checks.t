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
use Test::More;
use Carp;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use TestUtils;
use File::Find;

warning_fatal();
my @all;
find ( { wanted => sub {
	push @all, $_ if -f;
}, no_chdir => 1 }, "$FindBin::RealBin/../../lib");

ok scalar @all > 40;

for my $file (@all) {
	next unless $file =~ /\.pm$/;
	next if $file =~ /\bMtAws\.pm$/;
	open my $fh, "<", $file or confess;
	local $_;
	my $ok = 1;
	while (<$fh>) {
		# test with EU::MM prior to Y2009 regexps for version definitions
		next unless /(?<!\\)([\$*])(([\w\:\']*)\bVERSION)\b.*\=/;

		# Y2009 regexp
		#next if /^\s*(if|unless)/;

		print STDERR "Bad line $_\n";
		$ok = 0;
		last;

	}
	ok $ok, "EU::MM regexps ok: $file";
}

done_testing;

1;

