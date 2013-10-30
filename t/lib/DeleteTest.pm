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

package DeleteTest;

use strict;
use warnings;
use Test::Deep;
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::Delete;
use QueueHelpers;


sub expect_delete
{
	my ($j, $relfilename, $archive_id, %args_opts) = @_;
	
	my %args = (%args_opts);
	
	
	cmp_deeply my $res = $j->next,
		App::MtAws::QueueJobResult->full_new(
			task => {
				args => {
					relfilename => $relfilename,
					archive_id => $archive_id,
				},
				action => 'delete_archive',
				cb => test_coderef,
				cb_task_proxy => test_coderef,
			},
			code => JOB_OK,
		);
	
	expect_wait($j);
	call_callback($res);
}


1;
