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
Adds one or several RULES to the list of rules. 
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
6) When wildcard '**' meant to be a separated path component (i.e. surrounded with slashes/beginning of line/end of line), it matches 0 or more subdirectories
7) Wildcard '?' matches any character except a slash (/).
8) if the pattern contains a / (not counting a trailing /) then it is matched against the full pathname, including any leading directories.
Otherwise it is matched only against the final component of the filename.
9) if PATTERN is empty, it matches anything.
10) If PATTERN is started with '!' it only match when rest of pattern (i.e. without '!') does not match.

(IV)

How rules are processed:

1) A filename is checked agains all rules in the list. Once filename match PATTERN, file is included or excluded depending of what kind of PATTERN matched.
No other rules checked after first match.

2) When traverse directory tree, unlike Rsync, if a directory (and all subdirectories) match exclude pattern, process is not stopped. So

--filter '+/tmp/data/a/b/c -/tmp/data -' will work (it will match /tmp/data/a/b/c)

3) In some cases, to reduce disk IO, directory traversal into excluded directory can be stopped.
This only can happen when mtgalcier absolutely sure that it won't break (2) behaviour.
It's guaraneed that traversal stop only in case when
a) directory match EXCLUDE rule without '!' prefix, ending with '/' or '**', or empty rule
"dir/"
"/some/dir/"
"prefix**
"/some/dir/prefix**
b) AND there is no INCLUDE rules before this exclude RULE

4) When we process both local files and Journal filelist (sync, restore commands), rule applied to BOTH sides.
 
=cut

package App::MtAws::Filter;

our $VERSION = '1.055';

use strict;
use warnings;
use utf8;
use Carp;

require Exporter;
use base qw/Exporter/;


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	
	$self->_init_substitutions(
		"\Q**\E" => '.*',
		"\Q/**/\E" => '(/|/.*/)',
		"\Q*\E" => '[^/]*',
		"\Q?\E" => '[^/]'
	);
	
	return $self;
}
				
sub check_filenames
{
	my $self = shift;
	map {
		my ($res, $subdir) = $self->check_dir($_);
		$res ? $_ : ();
	} @_;
}

sub check_dir
{
	my ($self, $dir) = @_;
	my $res = 1; # default action - include!
	my $match_subdirs = undef;
	for my $filter (@{$self->{filters}}) {
		$match_subdirs = 0 if ($filter->{action} eq '+'); # match_subdirs true only when we exclude this filename and we can to exclude all subdirs
		if ($filter->{notmatch} ? ("/$dir" !~ $filter->{re}) : ("/$dir" =~ $filter->{re})) {
			$res = !!($filter->{action} eq '+');
			$match_subdirs = $filter->{match_subdirs} unless defined $match_subdirs;
			last;
		}
	}
	return $res, $match_subdirs;
}

sub parse_filters
{
	my $self = shift;
	my @patterns = $self->_filters_to_pattern(@_);
	return unless @patterns;
	my @res = $self->_patterns_to_regexp(@patterns);
	push @{$self->{filters}}, @res;
}

sub parse_include
{
	my $self = shift;
	my @res = $self->_patterns_to_regexp({ pattern => shift(), action => '+'});
	push @{$self->{filters}}, @res;
}

sub parse_exclude
{
	my $self = shift;
	my @res = $self->_patterns_to_regexp({ pattern => shift(), action => '-'});
	push @{$self->{filters}}, @res;
}

sub _filters_to_pattern
{
	my $self = shift;
	map { # for each +/-PATTERN
	 # this will return arrayref with two elements: first + or -, second: the PATTERN
		/^\s*([+-])\s*(\S*)\s*$/ or confess "[$_]";
		{ action => $1, pattern => $2 }
	} map { # for each of filter arguments
		my @parsed = /\G(\s*[+-]\s*\S*\s*)/g;
		$self->{error} = $_, return unless @parsed; # regexp does not match
		$self->{error} = $', return if length($') > 0; # not all of the string parsed
		@parsed; # we can return multiple +/-PATTERNS for each filter argument
	} @_;
}

sub _init_substitutions
{
	my $self = shift;
	
	my %subst = @_; # we treat args as hash

	my (@all);
	while (my ($k, undef) = splice @_, 0, 2) { push @all, $k }; # but now we treat args as array

	$self->{all_re} = '('.join('|', map { quotemeta } @all ).')';
	$self->{subst} = \%subst;
}

sub _pattern_to_regexp
{
	my ($self, $pattern) = @_;
	my $notmatch = ($pattern =~ /^!/);
	$pattern =~ s/^!// if $notmatch; # TODO: optimize
	confess unless defined $pattern;
	return match_subdirs => !$notmatch, re => qr/.*/, notmatch => $notmatch unless length($pattern);

	my $re = quotemeta $pattern;
	$re =~ s!$self->{all_re}!$self->{subst}->{$&}!ge;
	$re = ($pattern =~ m!(/.)!) ? "^/?$re" : "(^|/)$re";
	$re .= '$' unless ($pattern =~ m!/$!);
	return match_subdirs => $pattern =~ m!(^|/|\*\*)$! && !$notmatch, re => qr/$re/, notmatch => $notmatch;
}

sub _patterns_to_regexp
{
	my $self = shift;
	# of course order of regexps is important
	# how regexps works:
	# http://perldoc.perl.org/perlretut.html#Grouping-things-and-hierarchical-matching
	map {
		{ (%$_, $self->_pattern_to_regexp($_->{pattern})) };
	} @_;
}


1;
