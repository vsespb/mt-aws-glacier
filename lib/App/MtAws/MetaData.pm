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

package App::MtAws::MetaData;

our $VERSION = '0.974';

use strict;
use warnings;
use utf8;
use Encode;

use MIME::Base64;
use JSON::XS;
use POSIX;
use Time::Local;

use constant MAX_SIZE => 1024;

=pod

MT-AWS-GLACIER metadata format ('x-amz-archive-description' field).

Function definitions:
=====================
base64url() input - byte sequence, output - byte sequence
	Is Base64 URL algorithm: http://en.wikipedia.org/wiki/Base64#URL_applications
	basically it's base64 but with '=' padding removed, characters '+', '/' replaced with '-', '_' resp. and no new lines.

json_utf8() - input - Hash, output - byte sequence
	JSON string in UTF-8 representation. Can contain not-escaped UTF-8 characters. Will not contain linefeed. Hash objects are unordered.
	
latin1_to_utf8() - input - byte sequence, output - byte sequence
	Treats input data as Latin1 (ISO 8859-1) encoded sequence and converts it to UTF-8 sequence

isoO8601() - input - time, output - character string
	ISOO8601 time in the following format YYYYMMDDTHHMMSSZ. Only UTC filezone. No leap seconds supported.
	When encoding isoO8601() mt-aws-glacier will not store leap seconds. When decoding from isoO8601 leap seconds are not supported (yet).

{'filename': FILENAME, 'mtime': iso8601(MTIME)}
	Hash with two keys: 'filename' and 'mtime'. Corresponds to JSON 'Object'.

Input data:
=====================

FILENAME (character string)
	Is a relative filename (no leading slash). Filename is taken from file system and treated as a character sequence
	with known encoding.
MTIME (time)
	is file last modification time with 1 second resolution. Can be below Y1970.
	Internal representation is epoch time, so it can be any valid epoch time (including negative values and zero). On some system it's
	32bit signed, on others 64bit signed, for some filesystems it's 34 bit signed etc.

Version 'mt2'
=====================

x-amz-archive-description = 'mt2' <space> base64url(json_utf8({'filename': FILENAME, 'mtime': iso8601(MTIME)}))

Version 'mt1'
=====================

x-amz-archive-description = 'mt1' <space> base64url(latin1_to_utf8(json_utf8({'filename': FILENAME, 'mtime': iso8601(MTIME)})))

This format actually contains a bug - data is double encoded. However it does not affect data integrity. UTF-8 double encoded data can be
perfectly decoded (see http://www.j3e.de/linux/convmv/man/) - that's why the bug was unnoticed during one month.
This format was in use starting from version 0.80beta (2012-12-27) till 0.84beta (2013-01-28).

NOTES:
=====================

1) This specification assumes that in our programming language we have two different types of Strings: Byte string (byte sequence) and Character strings.
Byte string is sequence of octets. Character string is an internal representation of sequence of characters. Character strings cannot have encodings
by definition - it's internal, encoding is known to language implementation.

Some programming languages (like Ruby) have different model, when every string is a sequence of bytes with a known encoding (or no encoding at all). 

2) According to this spec. Same (FILENAME,MTIME) values can produce different x-amz-archive-description, as JSON hash is unordered.

3) This specification explains how to _encode_ data (because it's a specification). However it's easy to
understant how to decode it back.

4) Path separator in filename is '/'

=cut

my $meta_coder = ($JSON::XS::VERSION >= 1.4) ?
	JSON::XS->new->utf8->max_depth(1)->max_size(MAX_SIZE) : # some additional abuse-protection
	JSON::XS->new->utf8; # it's still protected by length checking below

sub meta_decode
{
	my ($str) = @_;
	my ($marker, $b64) = split(' ', $str);
	if ($marker eq 'mt1') {
		return (undef, undef) unless length($b64) <= MAX_SIZE;
		return _decode_json(_decode_utf8(_decode_b64($b64)));
	} elsif ($marker eq 'mt2') {
		return (undef, undef) unless length($b64) <= MAX_SIZE;
		return _decode_json(_decode_b64($b64));
	} else {
		return (undef, undef);
	}
}

sub _decode_b64
{
	my ($str) = @_;
	my $res = eval {
		$str =~ tr{-_}{+/};
		my $padding_n = length($str) % 4;
		$str .= ('=' x (4 - $padding_n) ) if $padding_n;
		MIME::Base64::decode_base64($str);
	};
	return $@ eq '' ? $res : undef;
}

sub _decode_utf8
{
	my ($str) = @_;
	return unless defined $str;
	my $res = eval {
		decode("UTF-8", $str, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)
	};
	return $@ eq '' ? $res : undef;
}

sub _decode_json
{
	my ($str) = @_;
	return unless defined $str;
	my $h = eval {
		$meta_coder->decode($str)
	};
	if ($@ ne '') {
		return (undef, undef);
	} else {
		return (undef, undef) unless defined($h->{filename}) && defined($h->{mtime});
		my $mtime = _parse_iso8601($h->{mtime});
		return unless defined $mtime;
		return ($h->{filename}, $mtime);
	}
}



sub meta_encode
{
	my ($relfilename, $mtime) = @_;
	return unless defined($mtime) && defined($relfilename);
	my $res = "mt2 "._encode_b64(_encode_json($relfilename, $mtime));
	return if length($res) > MAX_SIZE;
	return $res;
}

sub _encode_b64
{
	my ($str) = @_;
	my $res = MIME::Base64::encode_base64($str,'');
	$res =~ s/=+\z//;
	$res =~ tr{+/}{-_};
	return $res;
}

sub _encode_utf8
{
	my ($str) = @_;
	return encode("UTF-8",$str,Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
}


sub _encode_json
{
	my ($relfilename, $mtime) = @_;
	
	return $meta_coder->encode({
		mtime => strftime("%Y%m%dT%H%M%SZ", gmtime($mtime)),
		filename => $relfilename
	}),
}

sub _parse_iso8601 # Implementing this as I don't want to have non-core dependencies
{
	my ($str) = @_;
	return unless $str =~ /^\s*(\d{4})[\-\s]*(\d{2})[\-\s]*(\d{2})\s*T\s*(\d{2})[\:\s]*(\d{2})[\:\s]*(\d{2})[\,\.\d]{0,10}\s*Z\s*$/i; # _some_ iso8601 support for now
	my ($year, $month, $day, $hour, $min, $sec) = ($1,$2,$3,$4,$5,$6);
	$sec = 59 if $sec == 60; # TODO: dirty workaround to avoid dealing with leap seconds
	my $res = eval { timegm($sec,$min,$hour,$day,$month - 1,$year) };
	return ($@ ne ' ') ? $res : undef;
}

1;

__END__
