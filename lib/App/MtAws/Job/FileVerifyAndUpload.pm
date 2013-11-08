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

package App::MtAws::Job::FileVerifyAndUpload;

our $VERSION = '1.058';

use strict;
use warnings;
use utf8;
use base qw/App::MtAws::Job/;
use App::MtAws::Job::FileCreate;
use Carp;
use App::MtAws::Exceptions;
use App::MtAws::Utils;
use App::MtAws::TreeHash;

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	defined($self->{filename})||die;
	defined($self->{relfilename})||die;
	defined($self->{delete_after_upload})||die;
	$self->{treehash}||die;
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
		return ("ok", App::MtAws::Task->new(id => "verify_file", action=>"verify_file", data => {
			map { $_ => $self->{$_} } qw/filename relfilename treehash/
		} ));
	}
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self, $task) = @_;
	if ($self->{raised}) {
		confess unless defined($task->{result}{match});
		if ($task->{result}{match}) {
			return ('done');
		} else {
			return ("ok replace", App::MtAws::Job::FileCreate->new(
				(map { $_ => $self->{$_} } qw/filename relfilename partsize/),
				$self->{delete_after_upload} ?
					(finish_cb => sub {
						App::MtAws::Job::FileListDelete->new(archives => [{
							archive_id => $self->{archive_id}, relfilename => $self->{relfilename}
						}])
					})
				:
					()
			));
		}
	} else {
		die;
	}
}

sub will_do
{
	my ($self) = @_;
	"Will VERIFY treehash and UPLOAD $self->{filename} if modified";
}

1;
