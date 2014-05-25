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

package BenchmarkTest;

use FindBin;
use lib "$FindBin::RealBin/../lib";
use strict;
use warnings;
use Test::More;

sub import
{
	my ($class, %args) = @_;
	plan(skip_all => "MT_BENCHMARK not set"), exit 0 unless $ENV{MT_BENCHMARK};
	my %opts = map { my ($k, $v) = split /:/; $k => $v } split /,/, $ENV{MT_BENCHMARK};
	plan tests => $args{tests};
}

1;
