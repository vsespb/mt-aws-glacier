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
use Test::More tests => 5;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../../", "$FindBin::RealBin/../../../lib";
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartCreate;
use TestUtils;

warning_fatal();

sub test_coderef { code sub { ref $_[0] eq 'CODE' } }

use Data::Dumper;

my $j = App::MtAws::QueueJob::MultipartCreate->new();
cmp_deeply my $res = $j->next, App::MtAws::QueueJobResult->full_new(task_args => [], code => JOB_OK, task_action => 'create_file', state => 'wait', task_cb => test_coderef);
cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
$res->{task_cb}->();
cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);
cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);


1;
