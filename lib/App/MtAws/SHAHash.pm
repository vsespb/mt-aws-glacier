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


package App::MtAws::SHAHash;

our $VERSION = '1.116';

use strict;
use warnings;
use Digest::SHA;
use Carp;

use constant ONE_MB => 1024*1024;
use Exporter 'import';
our @EXPORT_OK = qw/large_sha256_hex/;

sub _length
{
	length($_[0])
}

sub large_sha256_hex
{
	return Digest::SHA::sha256_hex($_[0]) if $Digest::SHA::VERSION ge '5.63'; # unaffected version

	my $size = _length($_[0]);
	my $chunksize = $_[1];

	unless ($chunksize) { # if chunk size unspecified
		if ($size <= 256*ONE_MB) {
			return Digest::SHA::sha256_hex($_[0]); # small data chunks unaffected
		} else {
			$chunksize = 4*ONE_MB; # perhaps need increase chunksize for very large $size
		}
	}

	my $sha = Digest::SHA->new(256);

	my $offset = 0;
	while ($offset < $size) {
		$sha->add(substr($_[0], $offset, $chunksize));
		$offset += $chunksize;
	}
	$sha->hexdigest;
}


1;
