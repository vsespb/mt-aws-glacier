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

package UploadMultipartTest;

use strict;
use warnings;
use Test::Deep;
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::UploadMultipart;
use App::MtAws::TreeHash;
use QueueHelpers;


sub expect_upload_multipart
{
	my ($j, $mtime, $partsize, $relfilename, $upload_id, %args_opts) = @_;
	
	my %args = (%args_opts);
	
	# TODO: also test that it works with mtime=0

	no warnings 'redefine';
	local *App::MtAws::QueueJob::MultipartCreate::init_file = sub {
		$_[0]->{fh} = 'filehandle';
		$_[0]->{mtime} = $mtime;
	};


	cmp_deeply my $create_resp = $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_OK, task => {
		args => { partsize => $partsize, mtime => $mtime, relfilename => $relfilename},
		action => 'create_upload', cb=> test_coderef, cb_task_proxy => test_coderef
	});

	expect_wait($j);

	$create_resp->{task}{cb_task_proxy}->({upload_id => $upload_id});

	my $n = 5;
	my @orig_parts = map { [$_*10, "hash $_", \"file $_"] } (1..$n);
	my @parts = @orig_parts;

	no warnings 'redefine';
	local *App::MtAws::QueueJob::MultipartPart::read_part = sub {
		my $p = shift @parts;
		if ($p) {
			shift->{position} += $partsize;
			return (1, @$p)
		} else {
			return;
		}
	};

	my @callbacks;
	for (@orig_parts) {
		my $res = $j->next;
		cmp_deeply $res,
			App::MtAws::QueueJobResult->full_new(
				task => {
					args => {
						start => $_->[0],
						upload_id => $upload_id,
						part_final_hash => $_->[1],
						relfilename => $relfilename,
						mtime => $mtime,
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

	local *App::MtAws::TreeHash::calc_tree = sub { shift->{tree} = "my_final_hash" };
	local *App::MtAws::TreeHash::get_final_hash = sub { shift->{tree} };

	while (my $cb = shift @callbacks) {
		$cb->();
		if (@callbacks) {
			expect_wait($j);
		} else {
			cmp_deeply my $finish_resp = $j->next,
				App::MtAws::QueueJobResult->full_new(
					task => {
						args => {
							filesize => $n*$partsize,
							upload_id => $upload_id,
							relfilename => $relfilename,
							final_hash => 'my_final_hash',
							mtime => $mtime,
						},
						action => 'finish_upload',
						cb => test_coderef,
						cb_task_proxy => test_coderef,
					},
					code => JOB_OK,
				);
			call_callback($finish_resp);
			last;
		}
	}


}


1;
