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

package App::MtAws::FileCreateJob;

use strict;
use warnings;
use utf8;
use base qw/App::MtAws::Job/;
use App::MtAws::FileUploadJob;
use File::stat;
use Time::localtime;
use Carp;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    defined($self->{filename})||die;
    defined($self->{relfilename})||die;
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
		my $filesize = -s $self->{filename};
		$self->{mtime} = stat($self->{filename})->mtime; # TODO: how could we assure file not modified when uploading btw?
		die "With current partsize=$self->{partsize} we will exceed 10000 parts limit for the file $self->{filename} (filesize $filesize)" if ($filesize / $self->{partsize} > 10000);
	    open my $fh, "<$self->{filename}" or confess "ERROR: unable to open task file $self->{filename} for reading: $!";
	    binmode $fh;
	    $self->{fh} = $fh;
		return ("ok", App::MtAws::Task->new(id => "create_upload",action=>"create_upload", data => { partsize => $self->{partsize}, relfilename => $self->{relfilename}, mtime => $self->{mtime} } ));
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	if ($self->{raised}) {
		return ("ok replace", App::MtAws::FileUploadJob->new(
			fh => $self->{fh},
			relfilename => $self->{relfilename},
			filename => $self->{filename},
			partsize => $self->{partsize},
			upload_id => $task->{result}->{upload_id},
			mtime => $self->{mtime},
		));
	} else {
		die;
	}
}
1;