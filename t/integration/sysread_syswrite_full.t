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
use Test::More tests => 90;
use Encode;
use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use App::MtAws::RdWr::Read;
use App::MtAws::RdWr::Readahead;
use App::MtAws::RdWr::Write;
use Encode;
use POSIX;
use TestUtils;
use Carp;
use Time::HiRes qw/usleep/;

warning_fatal();

{
	my $mtroot = get_temp_dir();

	for my $class (qw/App::MtAws::RdWr::Read App::MtAws::RdWr::Readahead/) {
		{
			open(my $tmp, ">", "$mtroot/infile") or confess;
			close $tmp;
			open(my $in, "<", "$mtroot/infile") or confess;

			my $in_rd = $class->new($in);

			is sysread($in, my $buf, 1), 0;
			is $buf, '', "sysread initialize buffer to empty string";

			is $in_rd->sysreadfull(my $buf2, 1), 0;
			is $buf2, '', "sysreadfull initialize buffer to empty string";

			is read($in, my $buf3, 1), 0;
			is $buf3, '', "read initialize buffer to empty string";

		}
		{
			open(my $tmp, ">", "$mtroot/infile") or confess;
			close $tmp;
			open(my $in, "<", "$mtroot/infile") or confess;

			my $in_rd = $class->new($in);

			is sysread($in, my $buf, 1, 2), 0;
			is $buf, "\x00\x00", "sysread zero-pads buffer";

			is $in_rd->sysreadfull(my $buf2, 1, 2), 0;
			is $buf2, "\x00\x00", "sysreadfull zero-pads buffer";

			is read($in, my $buf3, 1, 2), 0;
			is $buf3, "\x00\x00", "read zero-pads buffer";
		}
		{
			open(my $tmp, ">", "$mtroot/infile") or confess;
			close $tmp;
			open(my $in, "<", "$mtroot/infile") or confess;

			my $in_rd = $class->new($in);

			my $buf = "X";
			is sysread($in, $buf, 1, 2), 0;
			is $buf, "X\x00", "sysread zero-pads buffer";

			my $buf2 = "X";
			is $in_rd->sysreadfull($buf2, 1, 2), 0;
			is $buf2, "X\x00", "sysreadfull zero-pads buffer";

			my $buf3 = "X";
			is read($in, $buf3, 1, 2), 0;
			is $buf3, "X\x00", "read zero-pads buffer";
		}
	}
}

my $redef = 1;
my $is_ualarm = Time::HiRes::d_ualarm();

for my $redef (0, 1) {
	no warnings 'redefine';
	local *App::MtAws::RdWr::Read::sysreadfull = sub {
		read($_[0]->{fh}, $_[1], $_[2]);
	} if $redef;

	local *App::MtAws::RdWr::Write::syswritefull = sub {
		my $f = $_[0]->{fh};
		print ($f $_[1]) or confess "Error $! in print";
		length $_[1];
	} if $redef;


	{
		with_fork
			sub {
				my ($in, $out, $childpid) = @_;
				my $in_rd = App::MtAws::RdWr::Read->new($in);
				my $n = $in_rd->sysreadfull(my $x, 2);
				is $n, 2, "should merge two reads";
				is $x, 'zx', "should merge two reads";
				kill(POSIX::SIGUSR2, $childpid);
			},
			sub {
				my ($in, $out) = @_;
				my $out_wr = App::MtAws::RdWr::Write->new($out);
				$out_wr->syswritefull('z') == 1 or die "$$ bad syswrite";
				usleep 5_000;
				$out_wr->syswritefull('x') == 1  or die "$$ bad syswrite";
				usleep 10_000 while(1);
			};
	}

	{
		local $SIG{USR1} = sub { print "# SIG $$\n" };
		with_fork
			sub {
				my ($in, $out, $childpid) = @_;
				my $in_rd = App::MtAws::RdWr::Read->new($in);
				my $n = $in_rd->sysreadfull(my $x, 2);
				is $n, 1, "should return first data chunk";
				is $x, 'z', "should return first data chunk correct";
				$n = $in_rd->sysreadfull($x, 1);
				is $n, 0, "should return EOF";
			},
			sub {
				my ($in, $out, $ppid) = @_;
				my $out_wr = App::MtAws::RdWr::Write->new($out);
				$out_wr->syswritefull('z') == 1 or die "$$ bad syswrite";
			};
	}

	{
		local $SIG{USR1} = sub { print "# SIG $$\n" };
		with_fork
			sub {
				my ($in, $out, $childpid) = @_;
				my $in_rd = App::MtAws::RdWr::Read->new($in);
				my $n = $in_rd->sysreadfull(my $x, 2);
				is $n, 2, "should handle EINTR in sysread";
				is $x, 'zx', "should handle EINTR in sysread";
				kill(POSIX::SIGUSR2, $childpid);
			},
			sub {
				my ($in, $out, $ppid) = @_;
				my $out_wr = App::MtAws::RdWr::Write->new($out);
				usleep 30_000;
				kill(POSIX::SIGUSR1, $ppid);
				$out_wr->syswritefull('zx') == 2 or die "$$ bad syswrite";
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
				my $in_rd = App::MtAws::RdWr::Read->new($in);
				for (1..$n) {
					my $n = $in_rd->sysreadfull(my $x, $sample_l);
					is $n, $sample_l, "should handle EINTR in syswrite";
					ok $x eq $full_sample
				}
			},
			sub {
				my ($in, $out, $ppid) = @_;
				for (1..$n) {
					my $out_wr = App::MtAws::RdWr::Write->new($out);
					$is_ualarm ? Time::HiRes::ualarm($small_delay*$uratio) : alarm($small_delay);
					$out_wr->syswritefull($full_sample) == $sample_l or die "$$ bad syswrite";
					$is_ualarm ? Time::HiRes::ualarm(0) : alarm(0);
				}

			};
	}

}

1;

__END__
