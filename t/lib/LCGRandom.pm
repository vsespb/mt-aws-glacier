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
our @EXPORT = qw/lcg_srand lcg_rand lcg_irand lcg_shuffle/;

use Carp;

our $seed = undef;

sub lcg_srand
{
	my ($newseed, $cb) = @_;
	$newseed ||= 0;
	if ($cb) {
		local $seed = $newseed;
		$cb->();
	} else {
		$seed = $newseed;
	}
}

sub lcg_rand
{
	confess if @_;
	confess "seed uninitialized" unless defined $seed;
	use integer;
	return $seed = (1103515245 * $seed + 12345) % (1 << 31)
}

sub lcg_irand
{
	my ($a, $b) = @_;
	confess "should pass two arguments" unless @_ == 2;
	confess "b should be greater or equal than a" unless $b >= $a;
	my $r = lcg_rand();
	$a + $r % ($b - $a + 1);
}

sub lcg_shuffle {
	my @array = @_;
	my $i = @array;
	while (--$i) {
		my $j = lcg_irand(0, $i);
		@array[$i,$j] = @array[$j,$i];
	}
	@array;
}

1;
