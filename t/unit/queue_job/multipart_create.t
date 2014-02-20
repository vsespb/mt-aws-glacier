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
use Test::More tests => 34;
use Test::Deep;
use FindBin;
use POSIX;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartCreate;
use App::MtAws::Exceptions;
use QueueHelpers;



use Data::Dumper;

# test args validation
my %opts = (filename => '/path/somefile', relfilename => 'somefile', partsize => 1024*1024, stdin=>1);

{
	ok eval { App::MtAws::QueueJob::MultipartCreate->new( map { $_ => $opts{$_} } qw/filename relfilename partsize delete_after_upload/); 1; };

	# check for zero
	ok eval { App::MtAws::QueueJob::MultipartCreate->new((map { $_ => $opts{$_} } qw/relfilename partsize/), filename => 0); 1; };
	ok eval { App::MtAws::QueueJob::MultipartCreate->new((map { $_ => $opts{$_} } qw/filename partsize/), relfilename => 0); 1; };
	ok !eval { App::MtAws::QueueJob::MultipartCreate->new((map { $_ => $opts{$_} } qw/filename relfilename/), partsize => 0); 1; };

	ok !eval { App::MtAws::QueueJob::MultipartCreate->new( map { $_ => $opts{$_} } qw/relfilename partsize/); 1; };
	ok !eval { App::MtAws::QueueJob::MultipartCreate->new( map { $_ => $opts{$_} } qw/filename partsize/); 1; };
	ok !eval { App::MtAws::QueueJob::MultipartCreate->new( map { $_ => $opts{$_} } qw/filename relfilename/); 1; };

	# stdin stuff
	{
		my %o = map { $_ => $opts{$_} } qw/filename relfilename partsize stdin/;
		for (qw/stdin filename/) {
			local $o{$_}; delete $o{$_}; # perl 5.8/10 compat.
			ok eval { App::MtAws::QueueJob::MultipartCreate->new(%o); 1; };
		}
		{
			ok ! eval { App::MtAws::QueueJob::MultipartCreate->new(%o); 1; };
			like "$@", qr/filename xor stdin/;
		}
		{
			delete $o{stdin};
			delete $o{filename};
			ok ! eval { App::MtAws::QueueJob::MultipartCreate->new(%o); 1; };
			like "$@", qr/filename xor stdin/;
		}
	}
}

sub test_case
{
	my ($filename, $relfilename, $mtime, $partsize) = @_;
	no warnings 'redefine';
	local *App::MtAws::QueueJob::MultipartCreate::init_file = sub {
		$_[0]->{fh} = 'filehandle';
		$_[0]->{mtime} = $mtime;
	};
	my $j = App::MtAws::QueueJob::MultipartCreate->new(filename => $filename, relfilename => $relfilename, partsize => $partsize);
	cmp_deeply my $res = $j->next,
		App::MtAws::QueueJobResult->full_new(code => JOB_OK,
		task => { args => {partsize => $partsize, relfilename => $relfilename, mtime => $mtime},
		action => 'create_upload', cb => test_coderef, cb_task_proxy => test_coderef});
	cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_WAIT);
	expect_wait($j);
	call_callback($res, upload_id => "someuploadid");
	expect_done($j);
	is $j->{upload_id}, "someuploadid";
}

test_case('/path/somefile', 'somefile', 123456, 2*1024*1024);
test_case('/path/somefile', 'somefile', 0, 2*1024*1024);
test_case('0', '0', 123456, 2*1024*1024);


1;
