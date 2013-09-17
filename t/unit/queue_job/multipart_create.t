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
use Test::More tests => 6;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../../", "$FindBin::RealBin/../../../lib";
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartCreate;
use TestUtils;

warning_fatal();

sub test_coderef { code sub { ref $_[0] eq 'CODE' } }

use Data::Dumper;

{
	no warnings 'redefine';
	local *App::MtAws::QueueJob::MultipartCreate::init_file = sub {
		$_[0]->{fh} = 'filehandle';
		$_[0]->{mtime} = 123456;
	};

	my $partsize = 2*1024*1024;
	my $j = App::MtAws::QueueJob::MultipartCreate->new(filename => '/somedir/somefile', relfilename => 'somefile', partsize => $partsize);
	cmp_deeply my $res = $j->next,
		App::MtAws::QueueJobResult->full_new(code => JOB_OK,
		task => { args => {partsize => $partsize, relfilename => 'somefile', mtime => 123456},
		action => 'create_upload', cb => test_coderef, cb_task_proxy => test_coderef});
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
	$res->{task}{cb_task_proxy}->({upload_id => "someuploadid"});
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);
	is $j->{upload_id}, "someuploadid";
}

1;
