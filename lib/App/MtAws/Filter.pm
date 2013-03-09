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

=pod

(I)

filter, include, exclude options allow you to construct a list of RULES to select only certain files for the operation.


(II)

--filter
Adds one or several INCLUDE or EXCLUDE PATTERNS to list of rules. 
One filter value can contain multiple rules, it has same effect as multiple filter values with one RULE each.

--filter='RULE1 RULE2' --filter 'RULE3'
is same as
--filter 'RULE1 RULE2 RULE3'

RULES: [+-]PATTERN [+-]PATTERN ...

RULES should be a sequence of PATTERNS, prepended with '+' or '-' and separated by a spaces.
There can be a space between '+'/'-' and PATTERN.

'+' means INCLUDE PATTERN, '-' means EXCLUDE PATTERN

Note: If RULES contain spaces or wildcards, you must quote it 
Note: although, PATTERN can contain spaces, you cannot use if, because RULES separated by a space(s).
Note: PATTERN can be empty 


--include=PATTERN
Adds an INCLUDE PATTERN to list of rules

--exclude=PATTERN
Adds an EXCLUDE PATTERN to list of rules

Note: If RULES contain spaces or wildcards, you must quote it 
Note: You can use spaces in PATTERNs here 

(III)

PATTERN:

1) if the pattern starts with a / then it is anchored to a particular spot in the hierarchy of files, otherwise it is matched against the final
component of the filename.
2) if the pattern ends with a / then it will only match a directory and all files/subdirectories inside this directory. It won't match regular file.
Note that if directory is empty, it won't be synchronized to Amazon Glacier, as it does not support directories
3) if pattern does not end with a '/', it won't match directory (directories are not supported by Amazon Glacier, so it has no sense to match a directory
without subdirectories). However if, in future versions we find a way to store empty directories in glacier, this behaviour could change.
4) Wildcard '*' matches any path component, but it stops at slashes.
5) Wildcard '**' matches anything, including slashes.
6) TBD: a '?' matches any character except a slash (/).
7) if the pattern contains a / (not counting a trailing /) then it is matched against the full pathname, including any leading directories.
Otherwise it is matched only against the final component of the filename.
8) if PATTERN is empty, it matches anything.
 
(IV)

How rules are processed:

1) A filename is checked agains all rules in the list. Once filename match PATTERN, checking is stopped, and file is included or excluded depending of what
kind of PATTERN matched.

2) When traverse directory tree, unlike Rsync, if a directory (and all subdirectories) match exclude pattern, process is not stopped. So

--filter '+/tmp/data/a/b/c -/tmp/data -' will work (it will match /tmp/data/a/b/c)

3) In some cases, to reduce disk IO, directory traversal into excluded directory can be stopped.
This only can happen when mtgalcier absolutely sure that it won't break (2) behaviour.
It's guaraneed that traversal stop only in case when
a) directory match EXCLUDE rule, ending with '/' or '**', or empty rule
"dir/"
"/some/dir/"
"prefix**
"/some/dir/prefix**
b) AND there is no INCLUDE rule before this exclude RULE

4) When we process both local files and Journal filelist (sync, restore commands), rule applied to BOTH sides.
 
=cut

package App::MtAws::Filter;

use strict;
use warnings;
use utf8;
use Carp;

require Exporter;
use base qw/Exporter/;

our @EXPORT_OK = qw/parse_filters _filters_to_pattern _patterns_to_regexp _substitutions/;
				



sub parse_filters
{
	my ($res, $error) = _filters_to_pattern(@_);
	return undef, $error if defined $error;
	_patterns_to_regexp(@$res);
	return $res, undef;
}


# '+abc -*.gz +'
# '+ abc - *.gz


sub _filters_to_pattern
{
	[map { # for each +/-PATTERN
	 # this will return arrayref with two elements: first + or -, second: the PATTERN
		 /\s*([+-])\s*([^+ ]+)\s*/ or confess;
		 { action => $1, pattern => $2 }
	} map { # for each of filter arguments
		my @parsed = /\G(\s*[+-]\s*\S+\s*)/g;
		return undef, $_ unless @parsed; # regexp does not match
		return undef, $' if length($') > 0; # not all of the string parsed
		@parsed; # we can return multiple +/-PATTERNS for each filter argument 
	} @_], undef;
}

sub _substitutions
{
	my %subst = @_; # we treat args as hash
	$subst{quotemeta($_)} = delete $subst{$_} for keys %subst; # replace keys with escaped versions

	my (@all);
	while (my ($k, undef) = splice @_, 0, 2) { push @all, $k }; # but now we treat args as array

	my $all_re = '('.join('|', map { quotemeta quotemeta } @all ).')';
	return $all_re, \%subst;
}

sub _pattern_to_regexp
{
	my ($filter, $all, $subst) = @_;
	confess unless defined $filter;
	return match_subdirs => 1, re => qr// unless length($filter);

	my $re = quotemeta $filter;
	$re =~ s!$all!$subst->{$&}!ge;
	$re = ($filter =~ m!(/.)!) ? "^/?$re" : "(^|/)$re";
	$re .= '$' unless ($filter =~ m!/$!);
	return match_subdirs => !!($filter =~ m!(^|/|\*\*)$!), re => qr/$re/;
}

sub _patterns_to_regexp
{
	my ($all, $subst) = _substitutions('**' => '.*', '*' => '[^/]*');
	map {
		%$_ = (%$_, _pattern_to_regexp($_->{pattern}, $all, $subst));
		$_;
	} @_;
}


1;
