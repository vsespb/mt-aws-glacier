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

package App::MtAws::IntermediateFile;

our $VERSION = '0.975';

use strict;
use warnings;
use utf8;
use Carp;
use File::Temp 0.16 ();
use File::Path;
use File::Basename;
use App::MtAws::Utils;
use App::MtAws::Exceptions;


sub new
{
	my ($class, %args) = @_;
	my $self = {};
	defined ($self->{target_file} = delete $args{target_file}) or confess "target_file expected";
	$self->{mtime} = delete $args{mtime};
	confess "unknown arguments" if %args;
	bless $self, $class;
	$self->_init();
	$self->{_init_pid} = $$;
	return $self;
}

sub _init
{
	my ($self) = @_;
	my $dir  = dirname($self->{target_file});
	my $binary_dirname = binaryfilename $dir;
	eval { mkpath($binary_dirname); 1 } or do {
		die exception 'cannot_create_directory' =>
		'Cannot create directory %string dir%, errors: %error%',
		dir => $dir, error => hex_dump_string($@);
	};
	$self->{tmp} = eval {
		# PID is needed cause child processes re-use random number generators, improves performance only, no risk of race cond.
		File::Temp->new(TEMPLATE => "__mtglacier_temp${$}_XXXXXX", UNLINK => 1, SUFFIX => '.tmp', DIR => $binary_dirname)
	} or do {
		die exception 'cannot_create_tempfile' =>
		'Cannot create temporary file in directory %string dir%, errors: %error%',
		dir => $dir, error => hex_dump_string($@);
	};
	my $binary_tempfile = $self->{tmp}->filename;
	$self->{tempfile} = characterfilename($binary_tempfile);
	 # it's important to close file, it's filename can be passed to different process, and it can be locked
	close $self->{tmp} or confess;
}

sub tempfilename
{
	shift->{tempfile} or confess;
}

sub make_permanent
{
	my $self = shift;
	confess "unknown arguments" if @_;
	my $binary_target_filename = binaryfilename($self->{target_file});

	my $character_tempfile = delete $self->{tempfile} or confess "file already permanent or not initialized";
	$self->{tmp}->unlink_on_destroy(0);
	undef $self->{tmp};
	my $binary_tempfile = binaryfilename($character_tempfile);

	chmod((0666 & ~umask), $binary_tempfile) or confess "cannot chmod file $character_tempfile";
	utime $self->{mtime}, $self->{mtime}, $binary_tempfile or confess "cannot change mtime for $character_tempfile" if defined $self->{mtime};
	rename $binary_tempfile, $binary_target_filename or
		die exception "cannot_rename_file" => "Cannot rename file %string from% to %string to%",
		from => $character_tempfile, to => $self->{target_file};
}

# File::Temp < 0.19 does not have protection from calling destructor in fork'ed child
# and forking can happen any moments, some code in File::Spec/Cwd etc call it to exec external commands
# this workaround prevents this, however destruction order is undefined so that might just fail

# we can try use File::Temp::tempfile() but it destroys temp files only on program exit
# (can workaround with DESTROY) + when handle is closed! (thats bad)
sub DESTROY
{
	my ($self) = @_;
	local ($!, $@, $?);
	eval { $self->{tmp}->unlink_on_destroy(0) }
		if ($self->{_init_pid} && $self->{_init_pid} != $$ && $self->{tmp});
}

1;
