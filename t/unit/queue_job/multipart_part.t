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
use Test::More tests => 174;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use LCGRandom;
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartPart;
use MyQueueEngine;
use QueueHelpers;




use Data::Dumper;

# test args validation
{
	my %opts = (
		relfilename => 'somefile',
		partsize => 2,
		mtime => 456,
		upload_id => 'abc',
		fh => { mock => 1},
		stdin => 0,
	);

	ok eval { my $j = App::MtAws::QueueJob::MultipartPart->new(%opts); 1 };

	for my $exclude_opt (sort keys %opts) {
		ok exists $opts{$exclude_opt};
		ok ! eval { App::MtAws::QueueJob::MultipartPart->new( map { $_ => $opts{$_} } grep { $_ ne $exclude_opt } keys %opts ); 1; },
			"should not work without $exclude_opt";
	}

	for my $non_zero_opt (qw/partsize upload_id fh/) {
		ok exists $opts{$non_zero_opt};
		ok ! eval { App::MtAws::QueueJob::MultipartPart->new(%opts, $non_zero_opt => 0); 1; },
	}

	for my $zero_opt (qw/relfilename mtime/) {
		ok exists $opts{$zero_opt};
		local $opts{$zero_opt} = 0;
		ok eval { App::MtAws::QueueJob::MultipartPart->new( %opts ); 1; }, "should work with $zero_opt=0";
	}

	ok eval { App::MtAws::QueueJob::MultipartPart->new( %opts, stdin => 0 ); 1; }, "should work with stdin 0";
	ok eval { App::MtAws::QueueJob::MultipartPart->new( %opts, stdin => 1 ); 1; }, "should work with stdin 1";
	ok eval { App::MtAws::QueueJob::MultipartPart->new( %opts, stdin => undef ); 1; }, "should work with stdin undef";
	{
		local $opts{stdin};
		delete $opts{stdin};
		ok !eval { App::MtAws::QueueJob::MultipartPart->new( %opts); 1; }, "should not work without stdin";
	}
}

sub test_case
{
	my ($n, $relfilename, $mtime, $test_cb) = @_;
	my @orig_parts = map { [$_*10, "hash $_", \"file $_"] } (0..$n);
	my @parts = @orig_parts;
	my %args = (relfilename => $relfilename, partsize => 2*1024*1024, upload_id => "someuploadid", fh => "somefh", mtime => $mtime, stdin => 1);

	no warnings 'redefine';
	local *App::MtAws::QueueJob::MultipartPart::read_part = sub {
		my $p = shift @parts;
		if ($p) {
			return (1, @$p)
		} else {
			return;
		}
	};

	my $j = App::MtAws::QueueJob::MultipartPart->new(%args);
	$test_cb->($j, \%args, \@orig_parts);
}


sub test_with_filename_and_mtime
{
	my ($relfilename, $mtime) = @_;

	# late finish (callbacks called in the end)

	test_case 15, $relfilename, $mtime, sub {
		my ($j, $args, $parts) = @_;
		my @callbacks;
		for (@$parts) {
			my $res = $j->next;
			cmp_deeply $res,
				App::MtAws::QueueJobResult->full_new(
					task => {
						args => {
							start => $_->[0],
							upload_id => $args->{upload_id},
							part_final_hash => $_->[1],
							relfilename => $args->{relfilename},
							mtime => $args->{mtime},
						},
						attachment => $_->[2],
						action => 'upload_part',
						cb => test_coderef,
						cb_task_proxy => test_coderef,
					},
					code => JOB_OK,
				);
			push @callbacks, $res->{task}{cb_task_proxy};
		}

		lcg_srand 444242 => sub {
			@callbacks = lcg_shuffle @callbacks; # late finish, but in random order

			while (my $cb = shift @callbacks) {
				$cb->();
				cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => @callbacks ? JOB_WAIT : JOB_DONE);
			}
		}
	};

	# early finish (early calls of callbacks)

	test_case 11, $relfilename, $mtime, sub {
		my ($j, $args, $parts) = @_;

		for (@$parts) {
			my $res = $j->next;
			cmp_deeply $res,
				App::MtAws::QueueJobResult->full_new(
					task => {
						args => {
							start => $_->[0],
							upload_id => $args->{upload_id},
							part_final_hash => $_->[1],
							relfilename => $args->{relfilename},
							mtime => $args->{mtime},
						},
						attachment => $_->[2],
						action => 'upload_part',
						cb => test_coderef,
						cb_task_proxy => test_coderef,
					},
					code => JOB_OK,
				);
			$res->{task}{cb_task_proxy}->();
		}
		cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);

	};
}

test_with_filename_and_mtime "somefile", 12345;
test_with_filename_and_mtime "somefile", 0;
test_with_filename_and_mtime 0, 12345;

# test case with early/late/random finish

{
	{
		package QE;
		use MyQueueEngine;
		use base q{MyQueueEngine};

		sub on_upload_part
		{
			my ($self, %args) = @_;
			push @{$self->{res}}, $args{part_final_hash};
		}
	};

	lcg_srand 4672 => sub {
		for my $n (1, 2, 15) {
			for my $workers (1, 2, 10, 20) {
				test_case $n, "somefile", 12345, sub {
					my ($j, $args, $parts) = @_;
					my $q = QE->new(n => $workers);
					$q->process($j);
					cmp_deeply [sort @{ $q->{res} }], [sort map { $_->[1] } @$parts];
				};
			}
		}
	}
}

1;
