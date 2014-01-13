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

package App::MtAws::QueueJob::DownloadSegments;

our $VERSION = '1.112';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use base 'App::MtAws::QueueJob';
use App::MtAws::IntermediateFile;

sub init
{
	my ($self) = @_;

	$self->{size}||confess;
	$self->{archive_id}||confess;
	$self->{jobid}||confess;
	$self->{file_downloads}{'segment-size'}||confess;
	defined($self->{relfilename})||confess;
	defined($self->{filename})||confess;
	defined($self->{mtime})||confess;

	$self->{position} = 0;
	$self->{segments} = {};

	$self->enter("tempfile");
	return $self;
}

sub on_tempfile
{
	my ($self) = @_;
	$self->{i_tmp} = App::MtAws::IntermediateFile->new(target_file => $self->{filename}, mtime => $self->{mtime});
	return state('download'), JOB_RETRY;
}

sub on_download
{
	my ($self) = @_;

	# uncoverable branch false count:3
	if ($self->{position} < $self->{size}) {
		my $download_size = $self->{size} - $self->{position};
		my $segment_size = $self->{file_downloads}{'segment-size'}*1048576 or confess;
		$download_size = $segment_size if $download_size > $segment_size;

		my $position_now = $self->{position}; # self->position will change, unlike position_now

		# uncoverable branch true
		confess if $self->{segments}{ $position_now }++;

		my @result = task "segment_download_job", {
			(map { $_ => $self->{$_} } qw/archive_id relfilename filename jobid/),
			position => $self->{position}, download_size => $download_size, tempfile => $self->{i_tmp}->tempfilename
		} => sub {
			delete $self->{segments}{ $position_now } or confess;
			return;
		};

		$self->{position} += $download_size;

		return @result;
	} elsif ($self->{position} == $self->{size}) {
		return state 'finishing';
	} else {
		confess; # uncoverable statement
	}
}

sub on_finishing
{
	my ($self) = @_;
	if (keys %{$self->{segments}}) {
		JOB_WAIT
	} else {
		$self->{i_tmp}->make_permanent;
		undef $self->{i_tmp}; # explicit destroy for very-very old File::Temp
		state('done');
	}
}

1;
