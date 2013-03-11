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

package App::MtAws::Utils;


use strict;
use warnings FATAL => 'all';
use utf8;
use File::Spec;
use Carp;
use Encode;

require Exporter;
use base qw/Exporter/;


our @EXPORT = qw/set_filename_encoding get_filename_encoding binaryfilename
sanity_relative_filename is_relative_filename open_file/;

# Does not work with directory names
sub sanity_relative_filename
{
	my ($filename) = @_;
	return undef unless defined $filename;
	return undef if $filename =~ m!^//!g;
	$filename =~ s!^/!!;
	return undef if $filename =~ m![\r\n\t]!g;
	$filename = File::Spec->catdir( map {return undef if m!^\.\.?$!; $_; } split('/', File::Spec->canonpath($filename)) );
	return undef if $filename eq '';
	return $filename;
}

sub is_relative_filename # TODO: test
{
	my ($filename) = @_;
	my $newname = sanity_relative_filename($filename);
	return defined($newname) && ($filename eq $newname); 
}


our $_filename_encoding = 'UTF-8'; # global var

sub set_filename_encoding($) { $_filename_encoding = shift };
sub get_filename_encoding() { $_filename_encoding || confess };

sub binaryfilename(;$)
{
	encode(get_filename_encoding, @_ ? shift : $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);	
}

#
# use_filename_encoding = 1
# not_empty
# mode
# file_encoding
# binary
sub open_file($%)
{
	my $filename = shift;
	my (%args) = (use_filename_encoding => 1, should_exist => 1, @_);
	
	confess "unknown mode $args{mode}" unless $args{mode} =~ m!^(<|>>?)$!;
	my $mode = $args{mode};
	
	confess "not_empty can be used in read mode only"
		if ($args{not_empty} && $args{mode} ne '<');
		
	
	if (defined($args{file_encoding})) {
		$mode .= ":encoding($args{file_encoding})";
		confess "cannot use binary and file_encoding at same time'" if $args{binary};
	} elsif (!$args{binary}) {
		confess "there should be file encoding or 'binary'";
	}
	
	if ($args{use_filename_encoding}) {
		$filename = binaryfilename $filename;
	}
	
	croak if -e $filename && (! -f $filename);
	croak if $args{not_empty} && (! -s $filename);
	
	open (my $f, $mode, $filename) || (!$args{should_exist} && return) || confess $filename;
	confess unless -f $f; # check for race condition - it was a file when we last checked, but now it's a directory
	confess if $args{not_empty} && (! -s $f);
	
	binmode $f if $args{binary};
	
	return $f;
}

sub file_size($%)
{
	my $filename = shift;
	my (%args) = (use_filename_encoding => 1, @_);
	if ($args{use_filename_encoding}) {
		$filename = binaryfilename $filename;
	}
	croak unless -f $filename;
	return -s $filename;
}

1;

__END__
