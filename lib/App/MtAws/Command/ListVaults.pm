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

package App::MtAws::Command::ListVaults;

our $VERSION = '1.120';

use strict;
use warnings;
use utf8;
use Carp;
use App::MtAws::ForkEngine qw/with_forks fork_engine/;
use App::MtAws::Utils;

use App::MtAws::QueueJob::ListVaults;

my @fields = qw/
SizeInBytes
CreationDate
VaultName
NumberOfArchives
LastInventoryDate
/;

sub run
{
	my ($options, $j) = @_;

	with_forks !$options->{'dry-run'}, $options, sub {
		if ($options->{'dry-run'}) {
			print "Will LIST VAULTS for current account\n"
		} else {
			my ($sum_number, $sum_size) = (0, 0);
			my $ft = App::MtAws::QueueJob::ListVaults->new();
			my ($R) = fork_engine->{parent_worker}->process_task($ft, undef);

			if ($options->{format} eq 'mtmsg') {
				for my $rec (@{$R->{all_vaults}}) {
					$sum_number += $rec->{NumberOfArchives};
					$sum_size += $rec->{SizeInBytes};
					for my $field (@fields) {
						if (exists $rec->{$field}) {
							my $value = $rec->{$field};
							$value = '' unless defined $value;
							print "MTMSG\tVAULT_LIST\t$rec->{VaultARN}\t$field\t$value\n";
						}
					}
				}
				print "MTMSG\tVAULTS_SUMMARY\ttotal_number_of_archives\t$sum_number\n";
				print "MTMSG\tVAULTS_SUMMARY\ttotal_size_of_archives\t$sum_size\n";
			} elsif ($options->{format} eq 'for-humans') {
				print "\n";
				for my $rec (@{$R->{all_vaults}}) {
					$sum_number += $rec->{NumberOfArchives};
					$sum_size += $rec->{SizeInBytes};

					print "Vault $rec->{VaultName} ($rec->{VaultARN})\n";
					print "Archives: $rec->{NumberOfArchives}, Size: $rec->{SizeInBytes}\n";
					print "Created: $rec->{CreationDate}\n";
					if (defined $rec->{LastInventoryDate}) {
						print "Last inventory generation date: $rec->{LastInventoryDate}\n";
					} else {
						print "Never had inventory generation\n";
					}
					print "\n";
				}
				print "Total archives in all listed vaults: $sum_number\n";
				print "Total size of archives in all listed vaults: $sum_size\n";
				print "\n";
			} else {
				confess "Unknown --format";
			}
		}
	}
}


1;

__END__
