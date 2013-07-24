#!/usr/bin/perl

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
use utf8;
use Test::Spec;
use Carp;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::GlacierRequest;
use App::MtAws::ChildWorker;
use App::MtAws::TreeHash;
use App::MtAws;
use Data::Dumper;
use TestUtils;
use File::Temp ();
use File::stat;

my $TEMP = File::Temp->newdir();
my $mtroot = $TEMP->dirname();

warning_fatal();

describe "retrieval_download_job" => sub {
	it "should deliver correct data" => sub {
		my $data_blob = 'aHJj2' x 123;
		my $data_size = length $data_blob;
		my $data_treehash = treehash_fast($data_blob);
		my $data_filename = "$mtroot/targed_file.txt";
		ok !-e $data_filename;

		my $C = bless { options => { region => 'rrr', key => 'kkk', secret => 'sss', protocol => 'http', timeout => 120, vault => 'vvv' } },
			'App::MtAws::ChildWorker';

		my $response = HTTP::Response->new(200);
		$response->header('x-amz-sha256-tree-hash' => $data_treehash);

		App::MtAws::GlacierRequest->expects('perform_lwp')->any_number->returns(sub {
			my ($self) = @_;
			$self->{writer}->reinit($data_size);
			$self->{writer}->add_data($data_blob);
			$self->{writer}->finish();
			return $response;
		});
		$C->process_task('retrieval_download_job', { jobid => 'myjobid', filename => $data_filename, size => $data_size, treehash => $data_treehash}, undef);

		is ( (stat($data_filename)->mode & 07777), (0666 & ~umask), "file should have default permissions");
		open(my $f, "<", $data_filename) or confess;
		my $got_data = do { local $/; <$f> };
		close $f;
		is $got_data, $data_blob;
	};
};


sub treehash_fast
{
	my $th = App::MtAws::TreeHash->new();
	$th->eat_data($_[0]);
	$th->calc_tree();
	return $th->get_final_hash();
}

runtests unless caller;

1;
