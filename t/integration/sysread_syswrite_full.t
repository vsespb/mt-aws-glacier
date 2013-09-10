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
use Test::More tests => 60;
use Encode;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::Utils;
use Encode;
use POSIX;
use TestUtils;
use Carp;
use Time::HiRes qw/usleep/;

#warning_fatal();

{
	my $mtroot = get_temp_dir();
	open(my $tmp, ">", "$mtroot/infile") or confess;
	close $tmp;
	open(my $in, "<", "$mtroot/infile") or confess;
	is sysread($in, my $buf, 1), 0;
	is $buf, '', "sysread initialize buffer to empty string";

	is sysreadfull($in, my $buf2, 1), 0;
	is $buf2, '', "sysreadfull initialize buffer to empty string";

	is read($in, my $buf3, 1), 0;
	is $buf3, '', "read initialize buffer to empty string";
}

my $redef = 1;
my $is_ualarm = Time::HiRes::d_ualarm();

for my $redef (0, 1) {
	no warnings 'redefine';
	local *sysreadfull = sub {
		read($_[0], $_[1], $_[2]);
	} if $redef;

	local *syswritefull = sub {
		my $f = $_[0];
		print ($f $_[1]) or confess "Error $! in print";
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
		local $SIG{USR1} = sub { print "# SIG $$\n" };
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
		local $SIG{USR1} = sub { print "# SIG $$\n" };
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

	SKIP: {
		skip "Cannot test in this configuration or due to some perl bugs", 20
			if $redef && (
				($^V lt v5.10.0) ||
				( ($^V ge v5.14.0) && ($^V le 5.16.0) ) ||
				(defined $ENV{PERLIO} && $ENV{PERLIO} =~ /stdio/)
			);

		local $SIG{ALRM} = sub { print "# SIG $$\n" };
		my $sample = 'abxhrtf6';
		my $full_sample = 'abxhrtf6' x (8192-7);
		my $sample_l = length $full_sample;
		my $n = 10;
		my $small_delay = 1;
		my $uratio = 100_000 / 10;

		with_fork
			sub {
				my ($in, $out, $childpid) = @_;
				$is_ualarm ? usleep($small_delay*2*$uratio) : sleep($small_delay*2);
				for (1..$n) {
					my $n = sysreadfull($in, my $x, $sample_l);
					is $n, $sample_l, "should handle EINTR in syswrite";
					ok $x eq $full_sample
				}
			},
			sub {
				my ($in, $out, $ppid) = @_;
				for (1..$n) {
					$is_ualarm ? Time::HiRes::ualarm($small_delay*$uratio) : alarm($small_delay);
					syswritefull($out, $full_sample) == $sample_l or die "$$ bad syswrite";
					$is_ualarm ? Time::HiRes::ualarm(0) : alarm(0);
				}

			};
	}

}

1;

__END__
