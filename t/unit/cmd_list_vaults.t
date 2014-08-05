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
use Test::More tests => 6;
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
		it "should work" => sub {
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
						LastInventoryDate => "2013-09-01T19:01:19.997Z",
						NumberOfArchives => 200,
						SizeInBytes => 200_500,
						VaultARN => "arn:aws:glacier:eu-west-1:112345678901:vaults/def",
						VaultName => "myvault2",
					}]
				}
			} )->once;

			my ($res, $out) = run_command({ concurrency => 1});
			ok $res;
			ok $out =~ /^MTMSG\tSizeInBytes\t100500$/m;
			ok $out =~ /^MTMSG\tSizeInBytes\t200500$/m;
			ok $out =~ /vaults\/def/m;
			ok $out =~ /vaults\/xyz/m;
		};
	};
};

runtests unless caller;

1;
