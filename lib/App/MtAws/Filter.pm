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

package App::MtAws::Filter;

use strict;
use warnings;
use utf8;

require Exporter;
use base qw/Exporter/;

our @EXPORT_OK = qw/_parse_filters/;
				


sub substitutions
{
	my %subst = @_; # we treat args as hash
	$subst{quotemeta($_)} = delete $subst{$_} for keys %subst; # replace keys with escaped versions

	my (@all);
	while (my ($k, undef) = splice @_, 0, 2) { push @all, $k }; # but now we treat args as array

	my $all_re = '('.join('|', map { quotemeta quotemeta } @all ).')';
	return $all_re, \%subst;
}

# '+abc -*.gz +'
# '+ abc - *.gz


sub _parse_filters
{
	[map {
		[ /\s*([+-])\s*([^+ ]+)\s*/ ] # this will return arrayref with two elements - first + or -, second - the filter
	} map {
		my @parsed = /\G(\s*[+-]\s*\S+\s*)/g;
		return undef, $_ unless @parsed;
		return undef, $' if !@parsed || (defined($') && length($') > 0);
		@parsed;
	} @_], undef;
}



sub filters_to_regexp
{
	my ($all, $subst) = substitutions('**' => '.*', '*' => '[^/]*');
	map { filter_to_regexp($_, $all, $subst) } @_;
}


sub filter_to_regexp
{
	my ($filter, $all, $subst) = @_;
	my $re = quotemeta $filter;
	$re =~ s!$all!$subst->{$&}!ge;
	$re = ($filter =~ m!(/.|\*\*)!) ? "^/?$re" : "(^|/)$re";
	$re .= '$' unless ($filter =~ m!/$!);
	qr/$re/;
}


1;
