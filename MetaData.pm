# mt-aws-glacier - AWS Glacier sync client
# Copyright (C) 2012  Victor Efimov
# vs@vs-dev.com http://vs-dev.com
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

package MetaData;

use strict;
use warnings;
use utf8;
use Encode;

use MIME::Base64 qw/encode_base64url decode_base64url/;
use JSON::XS;

=pod

MT-AWS-GLACIER metadata format (x-amz-archive-description field).

Version 'mt1'

x-amz-archive-description = 'mt1' <space> base64url(json({'filename': utf8(FILENAME), 'mtime': MTIME}))

base64url algorithm: http://en.wikipedia.org/wiki/Base64#URL_applications
json can contain UTF-8 not-escaped characters
json won't contain linefeed
MTIME is filename Epoch (Unix time) timestamp



=cut

# yes, a module, so we can unit-test it (JSON and YAML have different serialization implementeation)
my $meta_coder = JSON::XS->new->utf8->max_depth(1)->max_size(1024);

sub meta_decode
{
  my ($str) = @_;
  my ($marker, $b64) = split(' ', $str);
  if ($marker eq 'mt1') {
  	return (undef, undef) unless length($b64) <= 1024;
  	return _decode_json(_decode_b64($b64));
  } else {
  	return (undef, undef);
  }
}

sub _decode_b64
{
	my ($str) = @_;
	my $res = eval {
		decode("UTF-8", decode_base64url($str), Encode::DIE_ON_ERR|Encode::LEAVE_SRC)
	};
	return $@ eq '' ? $res : undef;
}

sub _decode_json
{
	my ($str) = @_;
	my $h = eval { 
		$meta_coder->decode($str)
	};
	if ($@ ne '') {
		return (undef, undef);
	} else {
		return (undef, undef) unless defined($h->{filename}) && defined($h->{mtime});
		return (undef, undef) unless $h->{mtime} >= 0;
		return ($h->{filename}, $h->{mtime});
	}
}



sub meta_encode
{
	my ($relfilename, $mtime) = @_;
	return undef unless defined($mtime) && defined($relfilename) && $mtime >= 0;
	my $res = "mt1 "._encode_b64(_encode_json($relfilename, $mtime));
	return undef if length($res) > 1024;
	return $res;
}

sub _encode_b64
{
	my ($str) = @_;
	return encode_base64url(encode("UTF-8",$str,Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
}

sub _encode_json
{
	my ($relfilename, $mtime) = @_;
	
	$meta_coder->encode({
		mtime => $mtime+0,
		filename => $relfilename
	}),
}

1;

__END__
