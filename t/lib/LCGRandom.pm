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

package LCGRandom;

use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use strict;
use warnings;

use base 'Exporter';
our @EXPORT = qw/lcg_srand lcg_rand/;

use Carp;

our $seed = 0;

sub lcg_srand {
	my ($newseed, $cb) = @_;
	$newseed ||= 0;
	if ($cb) {
		local $seed = $newseed;
		$cb->();
	} else {
		$seed = $newseed;
	}
}
sub lcg_rand { confess if @_; $seed = (1103515245 * $seed + 12345) % (1 << 31) }

1;
