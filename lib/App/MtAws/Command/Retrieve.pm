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

package App::MtAws::Command::Retrieve;

our $VERSION = '1.112';

use strict;
use warnings;
use utf8;
use Carp;
use App::MtAws::ForkEngine qw/with_forks fork_engine/;
use App::MtAws::Utils;

use App::MtAws::QueueJob::Retrieve;
use App::MtAws::QueueJob::Iterator;

sub next_retrieve
{
	my ($filelistref) = @_;
	if (my $rec = shift @{ $filelistref }) {
		return App::MtAws::QueueJob::Retrieve->new(map { $_ => $rec->{$_}} qw/archive_id filename relfilename/ );
	} else {
		return;
	}
}

sub run
{
	my ($options, $j) = @_;
	confess unless $j->{use_active_retrievals};
	with_forks !$options->{'dry-run'}, $options, sub {
		$j->read_journal(should_exist => 1);

		my @filelist = get_file_list($options, $j);

		if (@filelist) {
			if ($options->{'dry-run'}) {
				for (@filelist) {
					print "Will RETRIEVE archive $_->{archive_id} (filename $_->{relfilename})\n"
				}
			} else {
				my $ft = App::MtAws::QueueJob::Iterator->new(iterator => sub { next_retrieve(\@filelist) });
				$j->open_for_write();
				my ($R) = fork_engine->{parent_worker}->process_task($ft, $j);
				die unless $R;
				$j->close_for_write();
			}
		} else {
			print "Nothing to restore\n";
		}
	}
}

sub get_file_list # TODO: optimize as lazy code
{
	my ($options, $j) = @_;
	my $files = $j->{journal_h};
	# TODO: refactor
	my @filelist =
		grep { !$j->{active_retrievals}{$_->{archive_id}} && ! -f binaryfilename $_->{filename} }
		map { {archive_id => $_->{archive_id}, relfilename => $_->{relfilename}, filename=> $j->absfilename($_->{relfilename}) } }
		map { $j->latest($_) } # TODO: two maps is not effective
		keys %{$files};
	@filelist  = splice(@filelist, 0, $options->{'max-number-of-files'});
}

1;

__END__
