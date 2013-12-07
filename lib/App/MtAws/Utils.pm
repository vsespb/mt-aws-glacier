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

our $VERSION = '1.100';

use strict;
use warnings;
use utf8;
use File::Spec;
use File::stat;
use Carp;
use Encode;
use LWP::UserAgent;
use bytes ();

require Exporter;
use base qw/Exporter/;


our @EXPORT = qw/set_filename_encoding get_filename_encoding binaryfilename
sanity_relative_filename is_relative_filename open_file sysreadfull syswritefull hex_dump_string
is_wide_string characterfilename try_drop_utf8_flag dump_request_response file_size file_mtime file_exists/;

# Does not work with directory names
sub sanity_relative_filename
{
	my ($filename) = @_;
	return undef unless defined $filename;
	return undef if $filename =~ m!^//!g;
	$filename =~ s!^/!!;
	return undef if $filename =~ m![\r\n\t]!g;
	$filename = File::Spec->catdir( map {return undef if m!^\.\.?$!; $_; } split('/', File::Spec->canonpath($filename)) );
	return undef
		if !defined($filename) ||  # workaround https://rt.cpan.org/Public/Bug/Display.html?id=86624
			$filename eq '';
	return $filename;
}

sub is_relative_filename
{
	my ($filename) = @_;
	return unless (defined($filename) && length($filename));
	return if $filename =~ tr{\r\n\t}{} or index($filename, '//') != -1 or substr($filename, 0, 1) eq '/';
	return undef if $filename =~ m{
		(^|/)\.\.?(/|$)
	}x;
	1;
}


our $_filename_encoding = 'UTF-8'; # global var

sub set_filename_encoding($) { $_filename_encoding = shift };
sub get_filename_encoding() { $_filename_encoding || confess };

sub binaryfilename(;$)
{
	encode(get_filename_encoding, @_ ? shift : $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
}

sub characterfilename(;$)
{
	decode(get_filename_encoding, @_ ? shift : $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
}

=pod

open_file(my $f, $filename, %args)

$args{mode} - mode to open, <, > or >>
$args{use_filename_encoding} - (TRUE) - encode to binary string, (FALSE) - don't tocuh (already a binary string). Default TRUE
$args{file_encoding} or $args{binary} - file content encoding or it's a binary file (mutual exclusive)
$args{not_empty} - assert that file is not empty after open

Assertions made (using "confess"):

1) Bad arguments (programmer's error)
2) File is not a plain file
3) File is not a plain file, but after open (race conditions)
4) File is empty and not_empty specified
5) File is empty and not_empty specified, but after open (race conditions)

NOTE: If you want exceptions for (2) and (4) - check it before open_file. And additional checks inside open_file will
prevent race conditions

=cut

sub open_file($$%)
{
	(undef, my $filename, my %args) = @_;
	%args = (use_filename_encoding => 1, %args);
	my $original_filename = $filename;

	my %checkargs = %args;
	defined $checkargs{$_} && delete $checkargs{$_} for qw/use_filename_encoding mode file_encoding not_empty binary/;
	confess "Unknown argument(s) to open_file: ".join(';', keys %checkargs) if %checkargs;

	confess 'Argument "mode" is required' unless defined($args{mode});
	confess "unknown mode $args{mode}" unless $args{mode} =~ m!^\+?(<|>>?)$!;
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

	confess "File is not a plain file" if -e $filename && (! -f $filename);
	confess "File should not be empty" if $args{not_empty} && (! -s $filename);

	open ($_[0], $mode, $filename) or return;
	my $f = $_[0];

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
	confess "file not exists" unless -f $filename;
	return -s $filename;
}

sub file_exists($%)
{
	my $filename = shift;
	my (%args) = (use_filename_encoding => 1, @_);
	if ($args{use_filename_encoding}) {
		$filename = binaryfilename $filename;
	}
	return -f $filename;
}

sub file_mtime($%)
{
	my $filename = shift;
	my (%args) = (use_filename_encoding => 1, @_);
	if ($args{use_filename_encoding}) {
		$filename = binaryfilename $filename;
	}
	confess "file not exists" unless -f $filename;
	return stat($filename)->mtime;
}

sub is_wide_string
{
	defined($_[0]) && utf8::is_utf8($_[0]) && (bytes::length($_[0]) != length($_[0]))
}

# if we have ASCII-only data, let's drop UTF-8 flag in order to optimize some regexp stuff
# TODO: write also version which does not check is_utf8 - it's faster when utf8 always set
sub try_drop_utf8_flag
{
	Encode::_utf8_off($_[0]) if utf8::is_utf8($_[0]) && (bytes::length($_[0]) == length($_[0]));
}

sub sysreadfull($$$)
{
	my ($file, $len) = ($_[0], $_[2]);
	my $n = 0;
	while ($len - $n) {
		my $i = sysread($file, $_[1], $len - $n, $n);
		if (defined($i)) {
			if ($i == 0) {
				return $n;
			} else {
				$n += $i;
			}
		} elsif ($!{EINTR}) {
			redo;
		} else {
			return $n ? $n : undef;
		}
	}
	return $n;
}

sub syswritefull($$)
{
	my ($file, $len) = ($_[0], length($_[1]));
	confess if is_wide_string($_[1]);
	my $n = 0;
	while ($len - $n) {
		my $i = syswrite($file, $_[1], $len - $n, $n);
		if (defined($i)) {
			$n += $i;
		} elsif ($!{EINTR}) {
			redo;
		} else {
			return $n ? $n : undef;
		}
	}
	return $n;
}

sub hex_dump_string
{
	my ($str) = @_;
	my $isutf = is_wide_string($str);
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

sub dump_request_response
{
	my ($req, $resp) = @_;
	my $out = '';
	$out .= "===REQUEST:\n";
	$out .= join(" ", $req->method, $req->uri)."\n";

	my $req_headers = $req->headers->as_string;

	$req_headers =~ s!^(Authorization:.*Credential=)([A-Za-z0-9]+)/!$1***REMOVED***/!;
	$req_headers =~ s!^(Authorization:.*Signature=)([A-Za-z0-9]+)!$1***REMOVED***!;

	$out .= $req_headers;

	if ($req->content_type ne 'application/octet-stream' && $req->content && length($req->content)) {
		$out .= "\n".$req->content;
	}

	$out .= "\n===RESPONSE:\n";
	$out .= $resp->protocol." " if $resp->protocol;
	$out .= $resp->status_line."\n";
	$out .= $resp->headers->as_string;

	if ($resp->content_type eq 'application/json' && $resp->content && length($resp->content)) {
		$out .= "\n".$resp->content;
	}
	$out .= "\n\n";
	$out;
}

1;

__END__
