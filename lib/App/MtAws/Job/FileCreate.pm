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

package App::MtAws::Job::FileCreate;

our $VERSION = '1.059';

use strict;
use warnings;
use utf8;
use base qw/App::MtAws::Job/;
use App::MtAws::Job::FileUpload;
use File::stat;
use Time::localtime;
use Carp;
use App::MtAws::Exceptions;
use App::MtAws::Utils;

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	defined($self->{filename}) || $self->{stdin} || confess "no filename nor stdin";
	defined($self->{relfilename}) || confess "no relfilename";
	$self->{partsize}||die;
	$self->{raised} = 0;
	return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self) = @_;
	if ($self->{raised}) {
		return ("wait");
	} else {
		$self->{raised} = 1;

		if ($self->{stdin}) {
			$self->{mtime} = time();
			$self->{fh} = *STDIN;
		} else {
			my $binaryfilename = binaryfilename $self->{filename};
			my $filesize = -s $binaryfilename;

			die exception file_is_zero => "File size is zero (and it was not when we read directory listing). Filename: %string filename%",
				filename => $self->{filename}
					unless $filesize;

			$self->{mtime} = stat($binaryfilename)->mtime; # TODO: how could we assure file not modified when uploading btw?

			die exception too_many_parts =>
				"With current partsize=%d partsize%MiB we will exceed 10000 parts limit for the file %string filename% (file size %size%)",
				partsize => $self->{partsize}, filename => $self->{filename}, size => $filesize
					if ($filesize / $self->{partsize} > 10000);

			open_file($self->{fh}, $self->{filename}, mode => '<', binary => 1) or
				die exception upload_file_open_error => "Unable to open task file %string filename% for reading, errno=%errno%",
					filename => $self->{filename}, 'ERRNO';
		}
		return ("ok", App::MtAws::Task->new(id => "create_upload",action=>"create_upload", data => { partsize => $self->{partsize}, relfilename => $self->{relfilename}, mtime => $self->{mtime} } ));
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	if ($self->{raised}) {
		return ("ok replace", App::MtAws::Job::FileUpload->new(
			fh => $self->{fh},
			finish_cb => $self->{finish_cb},
			relfilename => $self->{relfilename},
			partsize => $self->{partsize},
			upload_id => $task->{result}->{upload_id},
			mtime => $self->{mtime},
		));
	} else {
		die;
	}
}

sub will_do
{
	my ($self) = @_;
	if (defined($self->{filename})) {
		"Will UPLOAD $self->{filename}";
	} elsif ($self->{stdin}) {
		"Will UPLOAD stream from STDIN";
	} else {
		confess;
	}
}
1;
