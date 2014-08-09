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
use utf8;

use FindBin;
use lib map { "$FindBin::RealBin/$_" } qw{../lib ../../lib};
use TestUtils 'w_fatal';

use Carp;
use POSIX;

use Test::Spec;
use Test::More;
use Test::Deep;

use Data::Dumper;

require App::MtAws::Command::ListVaults;

sub run_command
{
	my ($options) = @_;
	my $res = capture_stdout my $out => sub {
		no warnings 'redefine';
		return eval { App::MtAws::Command::ListVaults::run($options, undef); 1 };
	};
	return ($res, $out);
}


describe "command" => sub {
	describe "list_vaults" => sub {

		sub get_output
		{
			my (%add_opts) = @_;

			my $options = {concurrency => 1, %add_opts};

			App::MtAws::Command::ListVaults->expects("with_forks")->returns(sub{
				my ($flag, $opts, $cb) = @_;
				is $flag, !$options->{'dry-run'};
				is $options, $opts;
				$cb->();
			});

			App::MtAws::Command::ListVaults->expects("fork_engine")->returns(sub {
				bless { parent_worker =>
					bless {}, 'App::MtAws::ParentWorker'
				}, 'App::MtAws::ForkEngine';
			})->once;

			App::MtAws::ParentWorker->expects("process_task")->returns(sub {
				my ($self, $job) = @_;
				ok $self->isa('App::MtAws::ParentWorker');
				return {
					all_vaults => [{
						CreationDate => "2013-11-01T19:01:19.997Z",
						LastInventoryDate => "2013-10-01T19:01:19.997Z",
						NumberOfArchives => 100,
						SizeInBytes => 100_500,
						VaultARN => "arn:aws:glacier:eu-west-1:112345678901:vaults/xyz",
						VaultName => "myvault",
					}, +{
						CreationDate => "2013-10-01T19:01:19.997Z",
						LastInventoryDate => undef,
						NumberOfArchives => 200,
						SizeInBytes => 200_500,
						VaultARN => "arn:aws:glacier:eu-west-1:112345678901:vaults/def",
						VaultName => "myvault2",
					}]
				}
			} )->once;

			my ($res, $out) = run_command($options);
			ok $res;
			$out;
		}

		it "should work in mtmsg format" => sub {
			my $out = get_output(format => 'mtmsg');
			ok $out =~ m!^MTMSG\tVAULT_LIST\tarn:aws:glacier:eu-west-1:112345678901:vaults/xyz\tSizeInBytes\t100500$!m;
			ok $out =~ m!^MTMSG\tVAULT_LIST\tarn:aws:glacier:eu-west-1:112345678901:vaults/def\tSizeInBytes\t200500$!m;
			ok $out =~ /vaults\/def/m;
			ok $out =~ /vaults\/xyz/m;
			ok $out =~ m!^MTMSG\tVAULTS_SUMMARY\ttotal_number_of_archives\t300$!m;
			ok $out =~ m!^MTMSG\tVAULTS_SUMMARY\ttotal_size_of_archives\t301000$!m;
		};

		it "should work in for-humans format" => sub {
			my $out = get_output(format => 'for-humans');
			ok $out =~ m!^\QVault myvault (arn:aws:glacier:eu-west-1:112345678901:vaults/xyz)\E$!m;
			ok $out =~ m!^\QVault myvault2 (arn:aws:glacier:eu-west-1:112345678901:vaults/def)\E$!m;
			ok $out =~ m!^\QArchives: 100, Size: 100500\E$!m;
			ok $out =~ m!^\QArchives: 200, Size: 200500\E$!m;
			ok $out =~ m!^\QNever had inventory generation\E$!m;
			ok $out =~ m!^\QLast inventory generation date: 2013-10-01T19:01:19.997Z\E$!m;
			ok $out =~ m!Total archives in all listed vaults: 300!m;
			ok $out =~ m!Total size of archives in all listed vaults: 301000!m;
		};
	};
};

runtests unless caller;

1;
