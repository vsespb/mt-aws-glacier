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

package App::MtAws::SyncCommand;

use strict;
use warnings;
use utf8;
use Carp;
use constant ONE_MB => 1024*1024;
use App::MtAws::JobProxy;
use App::MtAws::JobListProxy;
use App::MtAws::FileCreateJob;
use App::MtAws::ForkEngine  qw/with_forks fork_engine/;
use App::MtAws::Journal;


sub run
{
	my ($options, $j) = @_;
	with_forks !$options->{'dry-run'}, $options, sub {
		$j->read_journal(should_exist => 0);
		$j->read_new_files($options->{'max-number-of-files'});
		
		if ($options->{'dry-run'}) {
			for (@{ $j->{newfiles_a} }) {
				my ($absfilename, $relfilename) = ($j->absfilename($_->{relfilename}), $_->{relfilename});
				print "Will UPLOAD $absfilename\n";
			}
		} else {
			$j->open_for_write();
			
			my @joblist;
			for (@{ $j->{newfiles_a} }) {
				my ($absfilename, $relfilename) = ($j->absfilename($_->{relfilename}), $_->{relfilename});
				my $ft = App::MtAws::JobProxy->new(job => App::MtAws::FileCreateJob->new(filename => $absfilename, relfilename => $relfilename, partsize => ONE_MB*$options->{partsize}));
				push @joblist, $ft;
			}
			if (scalar @joblist) {
				my $lt = App::MtAws::JobListProxy->new(jobs => \@joblist);
				my ($R) = fork_engine->{parent_worker}->process_task($lt, $j);
				die unless $R;
			}
			$j->close_for_write();
		}
	}
}


1;

__END__
