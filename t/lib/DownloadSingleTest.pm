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

package DownloadSingleTest;

use strict;
use warnings;
use Test::Deep;
use Carp;
use App::MtAws::QueueJobResult;
use QueueHelpers;


sub expect_download_single
{
	my ($j, %opts) = @_;
	exists($opts{$_}) or confess $_ for (qw/archive_id relfilename filename jobid size mtime treehash/);
	
	cmp_deeply my $res = $j->next,
		App::MtAws::QueueJobResult->full_new(
			task => {
				args => {
					%opts
				},
				action => 'retrieval_download_job',
				cb => test_coderef,
				cb_task_proxy => test_coderef,
			},
			code => JOB_OK,
		);
	
	expect_wait($j);
	call_callback($res);
}


1;
