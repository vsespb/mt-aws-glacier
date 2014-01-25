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

package App::MtAws::MetaData;

our $VERSION = '1.112';

use strict;
use warnings;
use utf8;
use Encode;

use MIME::Base64;
use JSON::XS;
use Time::Local;
use App::MtAws::Utils;

use constant MAX_SIZE => 1024;
use constant META_JOB_TYPE_FULL => 'full';

require Exporter;
use base qw/Exporter/;

our @EXPORT = qw/meta_decode meta_job_decode meta_encode meta_job_encode META_JOB_TYPE_FULL/;
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
	ISOO8601 time in the following format YYYYMMDDTHHMMSSZ. Only UTC timezone. No leap seconds supported.
	Supported year range is from 1000 to 9999
	When encoding isoO8601() mt-aws-glacier will not store leap seconds. When decoding from isoO8601 leap seconds will be dropped.

{'filename': FILENAME, 'mtime': iso8601(MTIME)}
	Hash with two keys: 'filename' and 'mtime'. Corresponds to JSON 'Object'.

Input data:
=====================

FILENAME (character string)
	Is a relative filename (no leading slash). Filename is taken from file system and treated as a character sequence
	with known encoding.
MTIME (time)
	is file last modification time with 1 second resolution. Can be below Y1970.
	Internal representation is epoch time, so it can be any valid epoch time (including negative values and zero).Supported
	range - from year 1000 to 9999 (inclusive)

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

my $meta_coder = ($JSON::XS::VERSION ge '1.4') ?
	JSON::XS->new->utf8->max_depth(1)->max_size(MAX_SIZE) : # some additional abuse-protection
	JSON::XS->new->utf8; # it's still protected by length checking below

sub meta_decode
{
	my ($str) = @_;
	return unless defined $str; # protect from undef $str

	my ($marker, $b64) = _split_meta($str);
	return unless defined $marker;
	if ($marker eq 'mt1') {
		return _decode_filename_and_mtime(_decode_json(_decode_utf8(_decode_b64($b64))));
	} elsif ($marker eq 'mt2') {
		return _decode_filename_and_mtime(_decode_json(_decode_b64($b64)));
	} else {
		return;
	}
}

sub meta_job_decode
{
	my ($str) = @_;
	return unless defined $str; # protect from undef $str

	my ($marker, $b64) = _split_meta($str);
	return unless defined $marker;
	if ($marker eq 'mtijob1') {
		_decode_jobs(_decode_json(_decode_b64($b64)));
	} else {
		return;
	}
}

sub _split_meta
{
	my ($str) = @_;
	my ($marker, $b64) = split(' ', $str); # split will return empty list if string is empty or contains spaces only
	return if !defined $b64 || length($b64) > MAX_SIZE;
	return ($marker, $b64);
}

sub _decode_b64
{
	my ($str) = @_;
	return eval {
		$str =~ tr{-_}{+/};
		my $padding_n = length($str) % 4;
		$str .= ('=' x (4 - $padding_n) ) if $padding_n;
		MIME::Base64::decode_base64($str);
	}; # undef if eval failed
}

sub _decode_utf8
{
	my ($str) = @_;
	return unless defined $str;
	return eval {
		decode("UTF-8", $str, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)
	};  # undef if eval failed
}

sub _decode_json
{
	my ($str) = @_;
	return unless defined $str;
	eval { $meta_coder->decode($str) }
}

sub _decode_filename_and_mtime
{
	my ($h) = @_;
	return unless defined $h;
	return unless defined($h->{filename}) && defined($h->{mtime});
	 # TODO: is that good to return undef everytime something missing? Maybe return error in case signature etc
	 # correct but time is broken - it's more robust.
	defined(my $mtime = _parse_iso8601($h->{mtime})) or return;
	return ($h->{filename}, $mtime);
}

sub _decode_jobs
{
	my ($h) = @_;
	return unless defined $h;
	return unless defined($h->{type});
	return ($h->{type});
}

sub meta_encode
{
	my ($relfilename, $mtime) = @_;
	return unless defined($mtime) && defined($relfilename);
	defined(my $res = _encode_b64(_encode_json(_encode_filename_and_mtime($relfilename, $mtime)))) or return;
	$res = "mt2 ".$res;
	return if length($res) > MAX_SIZE;
	return $res;
}

sub meta_job_encode
{
	my ($type) = @_;
	my $res = "mtijob1 "._encode_b64(_encode_json({ type => $type }));
	return if length($res) > MAX_SIZE;
	return $res;
}

sub _encode_b64
{
	my ($str) = @_;
	return unless defined $str;
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

sub _encode_filename_and_mtime
{
	my ($relfilename, $mtime) = @_;
	defined(my $iso = _to_iso8601($mtime)) or return;
	return {
		mtime => $iso,
		filename => $relfilename
	};
}

sub _encode_json
{
	my ($h) = @_;
	return unless defined $h;
	return $meta_coder->encode($h);
}


# iso8601 time parsing

use constant SEC_PER_DAY => 86400;
use constant YEARS_PER_CENTURY => 100;
use constant DAYS_PER_YEAR => 365;

sub is_leap
{
	($_[0] % 400 ==0) || ( ($_[0] % 100 != 0) && ($_[0] % 4 == 0) )
}

our %_leap_cache;
sub number_of_leap_years
{
	my ($y1, $y2, $m) = @_;
	$_leap_cache{$y1,$y2,$m} ||= do {
		my $cnt = 0;
		for ($y1+1..$y2-1) {
			$cnt++ if is_leap($_);
		}
		$cnt++ if ($m < 3 ) && is_leap($y1);
		$cnt++ if ($m >= 3) && is_leap($y2);
		$cnt;
	}
}

sub _to_iso8601
{
	my ($time) = @_;
	return if $time < -30610224000 || $time > 253402300799;
	my ($sec,$min,$hour,$mday,$mon,$year) = gmtime($time);
	 # strftime works bad on 32bit with Y2038 dates
	sprintf("%04d%02d%02dT%02d%02d%02dZ", 1900+$year, $mon+1, $mday, $hour, $min, $sec);
}

sub _parse_iso8601 # Implementing this as I don't want to have non-core dependencies
{
	my ($str) = @_;
	return unless $str =~ /^\s*(\d{4})[\-\s]*(\d{2})[\-\s]*(\d{2})\s*T\s*(\d{2})[\:\s]*(\d{2})[\:\s]*(\d{2})[\,\.\d]{0,10}\s*Z\s*$/i; # _some_ iso8601 support for now
	my ($year, $month, $day, $hour, $min, $sec) = ($1,$2,$3,$4,$5,$6);
	return if $year < 1000;
	my $leap = 0;
	$leap = $sec - 59, $sec = 59 if ($sec == 60 || $sec == 61);

	# some Y2038 bugs in timegm, workaround it. we need consistency across platforms and perl versions when parsing vault metadata
	if (!is_y2038_supported && (($year <= 1901) || ($year >= 2038)) ) {
		while ($year <= 1901) {
			$leap -= number_of_leap_years($year, $year + YEARS_PER_CENTURY, $month)*SEC_PER_DAY;
			$year += YEARS_PER_CENTURY;
			$leap -= YEARS_PER_CENTURY*SEC_PER_DAY*DAYS_PER_YEAR;
		}
		while ($year >= 2038) {
			$leap += number_of_leap_years($year - YEARS_PER_CENTURY, $year, $month)*SEC_PER_DAY;
			$year -= YEARS_PER_CENTURY;
			$leap += YEARS_PER_CENTURY*SEC_PER_DAY*DAYS_PER_YEAR;
		}
	}
	eval { timegm($sec,$min,$hour,$day,$month - 1,$year) + $leap };
}

1;

__END__
