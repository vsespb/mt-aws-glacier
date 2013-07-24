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

our $VERSION = '0.974';

use strict;
use warnings;
use utf8;
use Carp;
use File::Temp ();
use File::Path;
use App::MtAws::Utils;


sub new
{
	my ($class, %args) = @_;
	my $self = {};
	defined ($self->{dir} = delete $args{dir}) or confess "dir expected";
	bless $self, $class;
	$self->_init();
	return $self;
}

sub _init
{
	my ($self) = @_;
	my $binary_dirname = binaryfilename $self->{dir};
	mkpath($binary_dirname);
	$self->{tmp} = new File::Temp(TEMPLATE => '__mtglacier_temp_XXXXXX', UNLINK => 1, SUFFIX => '.tmp', DIR => $binary_dirname);
	my $binary_tempfile = $self->{tmp}->filename;
	$self->{character_tempfile} = characterfilename($binary_tempfile);
	 # it's important to close file, it's filename can be passed to different process, and it can be locked
	close $self->{tmp} or confess;
}

sub filename
{
	shift->{character_tempfile} or confess;
}

sub make_permanent
{
	my ($self, $filename) = @_;
	my $binary_target_filename = binaryfilename($filename);
	my $character_tempfile = delete $self->{character_tempfile} or confess "file already permanent or not initialized";
	$self->{tmp}->unlink_on_destroy(0);
	rename binaryfilename($character_tempfile), $binary_target_filename or confess "cannot rename file $character_tempfile to $filename";
	chmod((0666 & ~umask), $binary_target_filename) or confess "cannot chmod file $filename";
	undef $self->{tmp};
}

1;
