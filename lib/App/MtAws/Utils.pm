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
use POSIX;

require Exporter;
use base qw/Exporter/;


our @EXPORT = qw/set_filename_encoding get_filename_encoding binaryfilename
sanity_relative_filename is_relative_filename open_file sysreadfull syswritefull hex_dump_string exception dump_error extract_exception/;

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
	
	my %checkargs = %args;
	defined $checkargs{$_} && delete $checkargs{$_} for qw/use_filename_encoding should_exist mode file_encoding not_empty binary/;
	confess "Unknown argument(s) to open_file: ".join(';', keys %checkargs) if %checkargs;
	
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
	croak "File should not be empty" if $args{not_empty} && (! -s $filename);
	
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

sub sysreadfull($$$)
{
	my ($file, $len) = ($_[0], $_[2]);
	my $n = 0;
	while ($len - $n) {
		my $i = sysread($file, $_[1], $len - $n, $n);
		if (defined($i)) {
			if ($i == 0) {
				return 0;
			} else {
				$n += $i;
			}
		} elsif ($! == EINTR) {
			redo;
		} else {
			return undef;
		}
	}
	return $n;
}

sub syswritefull($$)
{
	my ($file, $len) = ($_[0], length($_[1]));
	my $n = 0;
	while ($len - $n) {
		my $i = syswrite($file, $_[1], $len - $n, $n);
		if (defined($i)) {
			$n += $i;
		} elsif ($! == EINTR) {
			redo;
		} else {
			return undef;
		}
	}
	return $n;
}

sub hex_dump_string
{
	my ($str) = @_;
	my $isutf = utf8::is_utf8($str) && length($str) != bytes::length($str);
	Encode::_utf8_off($str);
	$str =~ s/\\/\\\\/g;
	$str =~ s/\r/\\r/g;
	$str =~ s/\n/\\n/g;
	$str =~ s/\t/\\t/g;
	$str =~ s/\"/\\\"/g;
	$str =~ s/([[:cntrl:]]|[[:^ascii:]])/sprintf("\\x%02X",ord($1))/eg;
	$str = "\"$str\"";
	$str = "(UTF-8) ".$str if $isutf;
	$str;
}

sub exception
{
	my ($msg) = @_;
	return { 'MTEXCEPTION' => 1, message => $msg };
}

sub is_exception
{
	ref $@ eq ref {} && $@->{MTEXCEPTION};
}

sub extract_exception
{
	is_exception() ? $@->{message} : undef;
}

sub dump_error
{
	my ($where) = @_;
	$where = " ($where)" if $where;
	if (is_exception) {
		print STDERR "FATAL ERROR$where: $@->{message}\n";
	} else {
		print STDERR "UNEXPECTED ERROR $where: $@\n";
	}
}

1;

__END__
