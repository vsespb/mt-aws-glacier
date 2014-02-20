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
use Test::More tests => 27;
use Test::Deep;
use Carp;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::FetchAndDownload;
use LCGRandom;
use DeleteTest;
use QueueHelpers;
use JobListEmulator;



use Data::Dumper;

# test args validation

{
	ok eval { App::MtAws::QueueJob::FetchAndDownload->new(archives => [], file_downloads => {'segment-size' => 512 }); 1 };
	ok !eval { App::MtAws::QueueJob::FetchAndDownload->new(file_downloads => {'segment-size' => 512 }); 1 };
	ok !eval { App::MtAws::QueueJob::FetchAndDownload->new(archives => []); 1 };
}

{
	package QE;
	use MyQueueEngine;
	use base q{MyQueueEngine};

	sub new
	{
		my $class = shift;
		my $E = shift;
		my $self = $class->SUPER::new(@_);
		$self->{_E} = $E;
		$self;
	}

	sub on_retrieval_fetch_job
	{
		my ($self, %args) = @_;
		my $page = $self->{_E}->fetch_page($args{marker});
		{ response => $page };
	}

	sub on_retrieval_download_job
	{
		my ($self, %args) = @_;
		push @{ $self->{result_jobs}||=[] }, $args{jobid};
	}
};


sub test_case
{
	my ($E, $nworkers, $archives, $jobs) = @_;


	my $j = App::MtAws::QueueJob::FetchAndDownload->new(
		archives => {  map { $_ => {
			archive_id => $_, relfilename => "filename_$_", filename => "/tmp/path/filename_$_",
			size => 42, mtime => 123, treehash => 'abc',
		} } @$archives  },
		file_downloads => {'segment-size' => 512 },
	);

	my $q = QE->new($E, n => $nworkers);
	$q->process($j);

	cmp_deeply [sort @{$q->{result_jobs}}], $jobs;
}

lcg_srand 112234, sub {
	for my $before_archives (0, 2) {
		for my $after_archives (3, 5) {
			for my $duplicates (0, 1) {
				for my $nworkers (1, 2, 4) {
					my $E = JobListEmulator->new();
					$E->add_archive_fixture(2000+$_) for (1..$before_archives);
					$E->add_inventory_fixture(1000);
					$E->add_archive_fixture( 500+$_) for (1..$after_archives);
					if ($duplicates) {
						$E->add_archive_fixture( 500+$_) for (1..$after_archives);
					}

					test_case($E, 1,
						[qw/archive_501_1 archive_503_1 archive_503_2 archive_503_7/],
						[qw/j_501_1 j_503_1 j_503_2 j_503_7/]
					);
				}
			}
		}
	}
};

1;

__END__
