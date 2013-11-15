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
use Test::More tests => 754;
use Test::Deep;
use Data::Dumper;
use Carp;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadSegments;
use QueueHelpers;
use TestUtils;

use constant ONE_MB => 1024*1024;

warning_fatal();

sub test_case
{
	my ($size, $segment_size, $test_cb) = @_;
	no warnings 'redefine';
	local *App::MtAws::IntermediateFile::new = sub {
		bless { _mock => 1, data => \@_}, 'App::MtAws::IntermediateFile';
	};
	local *App::MtAws::IntermediateFile::tempfilename = sub {
		ok shift->{_mock};
		"sometempfilename";
	};
	local *App::MtAws::IntermediateFile::make_permanent = sub {
		ok $_[0]->{_mock};
		$_[0]->{_mock_permanent} = 1;
	};
	
	my %args = (size => $size, archive_id => 'abc', jobid => 'somejob', file_downloads => { 'segment-size' => $segment_size},
		relfilename => 'def', filename => '/path/def', mtime => 456);
	
	my $j = App::MtAws::QueueJob::DownloadSegments->new(%args);
	
	$test_cb->($j, { %args, tempfile => "sometempfilename" });
}


sub verify_parts
{
	my ($parts, $size, $segment_size, $expected_sizes) = @_;
	
	my @expected = $expected_sizes ? @$expected_sizes : ();
	
	# auto check that position that we're got are correct
	my $expect_position = 0;
	my $odd_size_seen = 0;
	for my $part (@$parts) {
		is $part->{position}, $expect_position;
		$expect_position += $part->{download_size};
		
		# manual check that position that we're got are correct
		is($part->{download_size}, shift @expected, "size matches next size in list") if $expected_sizes;
		
		if ($part->{download_size} != $segment_size * ONE_MB) {
			ok !$odd_size_seen, "current size down not match segment-size, but it's first time";
			$odd_size_seen = 1;
		}
	}
	is $expect_position, $size;
	is scalar @expected, 0;
}

sub verify_res
{
	my ($res, $args) = @_;
	cmp_deeply $res,
		App::MtAws::QueueJobResult->full_new(
			task => {
				args => {
					(map { $_ => $args->{$_} } qw/filename jobid relfilename archive_id tempfile/),
					download_size => code(sub{ shift > 0 }),
					position => code(sub{ defined shift }),
				},
				action => 'segment_download_job',
				cb => test_coderef,
				cb_task_proxy => test_coderef,
			},
			code => JOB_OK,
		);
	
}

# only test part sizes
sub test_case_lite
{
	my ($size, $segment_size, $expected_sizes) = @_;
	test_case $size, $segment_size, sub {
		my ($j, $args) = @_;
		
		my @parts;
	
		my $i = 0;
		while() {
			confess if $i++ > 1000;
			my $res = $j->next;
			if ($res->{code} eq JOB_OK) {
				push @parts, { download_size => $res->{task}{args}{download_size}, position => $res->{task}{args}{position} };
			} elsif ($res->{code} eq JOB_WAIT) {
				last;
			} else {
				confess;
			}
		}
		verify_parts(\@parts, $size, $segment_size, $expected_sizes);
	};
}


sub test_case_late_finish
{
	my ($size, $segment_size, $expected_sizes) = @_;
	test_case $size, $segment_size, sub {
		my ($j, $args) = @_;
		
		ok !defined($j->{i_tmp}), "tempfile object is not yet defined";
		
		my @parts;
	
		my $i = 0;
		while() {
			confess if $i++ > 1000;
			
			my $res = $j->next;
			ok $j->{i_tmp}, "tempfile object is defined";
			
			if ($res->{code} eq JOB_OK) {
				verify_res($res, $args);
				push @parts, { download_size => $res->{task}{args}{download_size}, position => $res->{task}{args}{position}, cb => $res->{task}{cb_task_proxy} };
			} elsif ($res->{code} eq JOB_WAIT) {
				last;
			} else {
				confess;
			}
		}

		verify_parts(\@parts, $size, $segment_size, $expected_sizes);

		my $remember_tempfile = $j->{i_tmp};
		ok $remember_tempfile, "tempfile object is defined";
		expect_wait($j); # again, wait
		$_->{cb}->() for (@parts);
		expect_done($j);
		ok $remember_tempfile->{_mock_permanent}, "tempfile now permanent"; # it's undef in $j, but we remembered it
		ok ! defined $j->{i_tmp}, "tempfile removed from job";
	};
}

sub test_case_early_finish
{
	my ($size, $segment_size, $expected_sizes) = @_;
	test_case $size, $segment_size, sub {
		my ($j, $args) = @_;
		
		ok !defined($j->{i_tmp}), "tempfile object is not yet defined";
		
		my @parts;
	
		my $i = 0;
		my $remember_tempfile;
		while() {
			confess if $i++ > 1000;
			
			my $res = $j->next;

			unless ($remember_tempfile) {
				ok $j->{i_tmp}, "tempfile object is defined";
				$remember_tempfile = $j->{i_tmp};
			}

			if ($res->{code} eq JOB_OK) {
				verify_res($res, $args);
				push @parts, { download_size => $res->{task}{args}{download_size}, position => $res->{task}{args}{position} };
				$res->{task}{cb_task_proxy}->();
			} elsif ($res->{code} eq JOB_DONE) {
				last;
			} else {
				confess;
			}
		}

		verify_parts(\@parts, $size, $segment_size, $expected_sizes);
		ok $remember_tempfile->{_mock_permanent}, "tempfile now permanent"; # it's undef in $j, but we remembered it
		ok ! defined $j->{i_tmp}, "tempfile removed from job";
	};
}

sub test_case_full
{
	my ($size, $segment_size, $expected_sizes) = @_;
	test_case_late_finish($size, $segment_size,  $expected_sizes);
	test_case_early_finish($size, $segment_size, $expected_sizes);
}

# manual testing segment sizes


test_case_full ONE_MB, 1, [ONE_MB];
test_case_full ONE_MB+1, 1, [ONE_MB, 1];
test_case_full ONE_MB-1, 1, [ONE_MB-1];


test_case_full 2*ONE_MB, 2, [2*ONE_MB];
test_case_full 2*ONE_MB+1, 2, [2*ONE_MB, 1];
test_case_full 2*ONE_MB+2, 2, [2*ONE_MB, 2];
test_case_full 2*ONE_MB-1, 2, [2*ONE_MB-1];
test_case_full 2*ONE_MB-2, 2, [2*ONE_MB-2];


test_case_full 4*ONE_MB, 2, [2*ONE_MB, 2*ONE_MB];
test_case_full 4*ONE_MB+1, 2, [2*ONE_MB, 2*ONE_MB, 1];
test_case_full 4*ONE_MB-1, 2, [2*ONE_MB, 2*ONE_MB-1];

# auto testing segment sizes

for my $segment (1, 2, 8, 16) {
	for my $size (2, 3, 15) {
		if ($size*ONE_MB <= 2*$segment*ONE_MB) { # avoid some unneeded testing
			for my $delta (-30, -2, -1, 0, 1, 2, 27) {
				test_case_lite $size*ONE_MB+$delta, $segment;
			}
		}
	}
}

1;

__END__
