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
use Test::More tests => 54;
use Encode;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Utils;
use Encode;
use POSIX;
use TestUtils;
use Time::HiRes qw/usleep ualarm/;

warning_fatal();

my $redef = 1;

for my $redef (0, 1) {
	no warnings 'redefine';
	local *sysreadfull = sub {
		read($_[0], $_[1], $_[2]);
	} if $redef;

	local *syswritefull = sub {
		my $f = $_[0];
		print $f $_[1];
		length $_[1];
	} if $redef;


	{
		with_fork
			sub {
				my ($in, $out, $childpid) = @_;
				my $n = sysreadfull($in, my $x, 2);
				is $n, 2, "should merge two reads";
				is $x, 'zx', "should merge two reads";
				kill(POSIX::SIGUSR2, $childpid);
			},
			sub {
				my ($in, $out) = @_;
				syswritefull($out, 'z') == 1 or die "$$ bad syswrite";
				usleep 5_000;
				syswritefull($out, 'x') == 1  or die "$$ bad syswrite";
				usleep 10_000 while(1);
			};
	}

	{
		local $SIG{USR1} = sub { print STDERR "SIG $$\n" };
		with_fork
			sub {
				my ($in, $out, $childpid) = @_;
				my $n = sysreadfull($in, my $x, 2);
				is $n, 1, "should return first data chunk";
				is $x, 'z', "should return first data chunk correct";
				$n = sysreadfull($in, $x, 1);
				is $n, 0, "should return EOF";
			},
			sub {
				my ($in, $out, $ppid) = @_;
				syswritefull($out, 'z') == 1 or die "$$ bad syswrite";
			};
	}

	{
		local $SIG{USR1} = sub { print STDERR "SIG $$\n" };
		with_fork
			sub {
				my ($in, $out, $childpid) = @_;
				my $n = sysreadfull($in, my $x, 2);
				is $n, 2, "should handle EINTR in sysread";
				is $x, 'zx', "should handle EINTR in sysread";
				kill(POSIX::SIGUSR2, $childpid);
			},
			sub {
				my ($in, $out, $ppid) = @_;
				usleep 30_000;
				kill(POSIX::SIGUSR1, $ppid);
				syswritefull($out, 'zx') == 2 or die "$$ bad syswrite";
				usleep 10_000 while(1);
			};
	}


	{
		local $SIG{ALRM} = sub { print STDERR "SIG $$\n" };
		my $sample = 'abxhrtf6';
		my $full_sample = 'abxhrtf6' x (8192-7);
		my $sample_l = length $full_sample;
		with_fork
			sub {
				my ($in, $out, $childpid) = @_;
				usleep 100_000;
				for (1..10) {
					my $n = sysreadfull($in, my $x, $sample_l);
					is $n, $sample_l, "should handle EINTR in syswrite";
					ok $x eq $full_sample
				}
			},
			sub {
				my ($in, $out, $ppid) = @_;
				for (1..10) {
					ualarm(10_000);
					syswritefull($out, $full_sample) == $sample_l or die "$$ bad syswrite";
					ualarm(0);
				}

			};
	}

}

1;

__END__
