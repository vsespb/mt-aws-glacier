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

package DownloadSegmentsTest;

use strict;
use warnings;
use TestUtils 'w_fatal';

use Exporter 'import';
our @EXPORT_OK=qw/test_case_full test_case_lite test_case_random_finish prepare_download_segments prepare_download prepare_mock ONE_MB/;


use Test::More;
use Test::Deep; # should be last line, after EXPORT stuff, otherwise versions ^(0\.089|0\.09[0-9].*) do something nastly with exports
use Data::Dumper;
use Carp;
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::DownloadSegments;
use App::MtAws::QueueJob::Download;
use QueueHelpers;
use LCGRandom;

use constant ONE_MB => 1024*1024;

sub prepare_mock
{
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
	shift->();
}

sub prepare_download_segments
{
	my ($size, $segment_size, $test_cb) = @_;
	prepare_mock sub {
		my %args = (size => $size, archive_id => 'abc', jobid => 'somejob', file_downloads => { 'segment-size' => $segment_size},
			relfilename => 'def', filename => '/path/def', mtime => 456);

		my $j = App::MtAws::QueueJob::DownloadSegments->new(%args);

		$test_cb->($j, 1, { %args, tempfile => "sometempfilename" });
	};
}

sub prepare_download
{
	my ($size, $segment_size, $test_cb) = @_;
	prepare_mock sub {
		my %args = (size => $size, archive_id => 'abc', jobid => 'somejob', file_downloads => { 'segment-size' => $segment_size},
			relfilename => 'def', filename => '/path/def', mtime => 456, treehash => 'wedontneedit');

		my $j = App::MtAws::QueueJob::Download->new(%args);

		$test_cb->($j, 0, { %args, tempfile => "sometempfilename" });
	}
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
		is($part->{download_size}, shift @expected, "size matches next size in list") if $expected_sizes; # _original_ sizes

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
	my ($prepare_cb, $size, $segment_size, $expected_sizes) = @_;
	$prepare_cb->($size, $segment_size, sub {
		my ($j, undef, $args) = @_;

		my @parts;

		my $i = 0;
		while() {
			confess if $i++ > 1000; # protection
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
	});
}


sub test_case_late_finish
{
	my ($prepare_cb, $size, $segment_size, $expected_sizes) = @_;
	$prepare_cb->($size, $segment_size, sub {
		my ($j, $check_tmpfile, $args) = @_;

		ok !defined($j->{i_tmp}), "tempfile object is not yet defined" if $check_tmpfile;

		my @parts;

		my $i = 0;
		while() {
			confess if $i++ > 1000;

			my $res = $j->next;

			ok $j->{i_tmp}, "tempfile object is defined" if $check_tmpfile;

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

		my $remember_tempfile;
		if ($check_tmpfile) {
			$remember_tempfile = $j->{i_tmp};
			ok $remember_tempfile, "tempfile object is defined";
		}
		expect_wait($j); # again, wait
		$_->{cb}->() for (@parts);
		expect_done($j);
		if ($check_tmpfile) {
			ok $remember_tempfile->{_mock_permanent}, "tempfile now permanent"; # it's undef in $j, but we remembered it
		}
		ok ! defined $j->{i_tmp}, "tempfile removed from job";
	});
}

sub test_case_early_finish
{
	my ($prepare_cb, $size, $segment_size, $expected_sizes) = @_;
	$prepare_cb->($size, $segment_size, sub {
		my ($j, $check_tmpfile, $args) = @_;

		ok !defined($j->{i_tmp}), "tempfile object is not yet defined" if $check_tmpfile;

		my @parts;

		my $i = 0;
		my $remember_tempfile;
		while() {
			confess if $i++ > 1000;

			my $res = $j->next;

			if ($check_tmpfile && !$remember_tempfile) {
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
		ok $remember_tempfile->{_mock_permanent}, "tempfile now permanent" if $check_tmpfile; # it's undef in $j, but we remembered it
		ok ! defined $j->{i_tmp}, "tempfile removed from job";
	});
}

{
	package QE;
	use MyQueueEngine;
	use base q{MyQueueEngine};

	sub on_segment_download_job
	{
		my ($self, %args) = @_;
		push @{$self->{res}}, { download_size => $args{download_size}, position => $args{position} };
	}
};

sub test_case_random_finish
{
	my ($prepare_cb, $size, $segment_size, $workers, $expected_sizes) = @_;
	$prepare_cb->($size, $segment_size, sub {
		my ($j, $args) = @_;
		my $q = QE->new(n => $workers);
		$q->process($j);
		verify_parts([ sort { $a->{position} <=> $b->{position} } @{ $q->{res} } ], $size, $segment_size, $expected_sizes);
	});
}



sub test_case_full
{
	my ($prepare_cb, $size, $segment_size, $expected_sizes) = @_;
	test_case_late_finish($prepare_cb, $size, $segment_size,  $expected_sizes);
	test_case_early_finish($prepare_cb, $size, $segment_size, $expected_sizes);
	test_case_random_finish($prepare_cb, $size, $segment_size, $_, $expected_sizes) for (1..4);
}


1;
