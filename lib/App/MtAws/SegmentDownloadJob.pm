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

package App::MtAws::SegmentDownloadJob;

use strict;
use warnings;
use utf8;
use base qw/App::MtAws::Job/;
use File::stat;
use Carp;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{archive}||die;
    $self->{pending}={};
    $self->{all_raised} = 0;
    $self->{position} = 0;
    return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;
	if ($self->{all_raised}) {
		return ("wait");
	} else {
		use Data::Dumper;
		#die Dumper  $self->{file_downloads};
		my $end_position = $self->{archive}{size} - 1;
		if ($self->{position} <= $end_position) {
			my $download_size = $end_position - $self->{position} + 1;
			$download_size = $self->{file_downloads}{'segment-size'} if $download_size > $self->{file_downloads}{'segment-size'};
			my $archive = $self->{archive};
			my $task = App::MtAws::Task->new(id => $self->{position}, action=>"segment_download_job", data => {
				archive_id => $archive->{archive_id}, relfilename => $archive->{relfilename},
				filename => $archive->{filename}, mtime => $archive->{mtime}, jobid => $archive->{jobid},
				position => $self->{position}, download_size => $download_size
			});
			$self->{position} += $download_size;
			$self->{uploadparts} ||= {};
			$self->{uploadparts}->{$task->{id}} = 1;
			return ("ok", $task);
		} elsif ($self->{position} == $end_position + 1) {
			confess "Unexpected: zero-size archive" unless ($self->{position});
			$self->{all_raised} = 1;
			if (scalar keys %{$self->{uploadparts}} == 0) {
				# TODO: why do we have to have two do_finish()?
				return $self->do_finish();
			} else {
				return ("wait");
			}
		} else {
			confess "$self->{position} != ".($end_position+1);
		}
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	# write taks->attachment to position position
	delete $self->{uploadparts}->{$task->{id}};
	if ($self->{all_raised} && scalar keys %{$self->{uploadparts}} == 0) {
		return $self->do_finish();
	} else {
		return ("ok");
	}
}

sub do_finish
{
	my ($self) = @_;
	my $mtime = $self->{archive}{mtime};
	utime $mtime, $mtime, $self->{archive}{filename} or confess if defined $mtime; # TODO: is that good that one process writes file and another one change it's mtime?
	return ("done");
}

1;
