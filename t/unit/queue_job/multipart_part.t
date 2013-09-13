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
use Test::More tests => 12;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../../", "$FindBin::RealBin/../../../lib";
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartPart;
use TestUtils;

warning_fatal();

sub test_coderef { code sub { ref $_[0] eq 'CODE' } }

use Data::Dumper;

{
	my @orig_parts = map { [$_*10, "hash $_", \"file $_"] } (0..5);
	my @parts = @orig_parts;
	my %args = (relfilename => 'somefile', partsize => 2*1024*1024, upload_id => "someuploadid", fh => "somefh", mtime => 12345);

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

	my $i = 0;
	my @callbacks;
	for (@orig_parts) {
		my $res = $j->next;
		cmp_deeply $res,
			App::MtAws::QueueJobResult->full_new(
				task_args => {
					start => $_->[0],
					upload_id => $args{upload_id},
					part_final_hash => $_->[1],
					relfilename => $args{relfilename},
					mtime => $args{mtime},
				},
				task_attachment => $_->[2],
				code => JOB_OK, task_action => 'upload_part', task_cb => test_coderef,
				$i ? () : (state => 'other_parts')
			);
		++$i;
		push @callbacks, $res->{task_cb};
	}

	while (my $cb = shift @callbacks) {
		$cb->();
		cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => @callbacks ? JOB_WAIT : JOB_DONE);
	}
}

1;
