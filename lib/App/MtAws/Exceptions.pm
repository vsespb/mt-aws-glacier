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

package App::MtAws::Exceptions;


use strict;
use warnings;
use utf8;
use Carp;

require Exporter;
use base qw/Exporter/;


our @EXPORT = qw/exception get_exception is_exception exception_message dump_error/;

# Does not work with directory names

# exception [$previous] { $msg | $code => $msg } @vars
sub exception
{
	my %data;
	%data = %{shift()} if (ref $_[0] eq ref {});
	if (scalar @_ == 1) {
		$data{message} = shift;
	} else {
		(@data{qw/code message/}, my %others) = @_;
		%data = (%data, %others);
	}
	return { 'MTEXCEPTION' => 1, %data };
}

# get_exception -> TRUE|FALSE
# get_exception($@)
# get_exception->{code}
sub get_exception
{
	my $e = @_ ? $_[0] : $@;
	ref $e eq ref {} && $e->{MTEXCEPTION} && $e;
}

# is_exception()
# is_exception($code)
# is_exception($code, $@)
sub is_exception
{
	my ($code, $e) = @_;
	$e = $@ unless defined $e;
	get_exception($e) &&
		(!defined($code) || ( defined(get_exception($e)->{code}) && get_exception($e)->{code} eq $code ));
}


sub exception_message
{
	my ($e) = @_;
	my %data = %$e;
	my $spec = delete $data{message};
	my $rep = sub {
		my ($match) = @_;
		if (my ($format, $name) = $match =~ /^([\w]+)\s+([\w]+)$/) {
			my $value = $data{$name};
			if (defined($value)) {
				if (lc $format eq lc 'string') {
					qq{"$value"};
				} else {
					sprintf("%$format", $value);
				}
			} else {
				':NULL:'
			}
		} else {
			defined($data{$match}) ? $data{$match} : ':NULL:';
		}
	};
	
	$spec =~ s{%([\w\s]+)%} {$rep->($1)}ge if %data; # in new perl versions \w also means unicode chars..
	$spec;
}



sub dump_error
{
	my ($where) = (@_, '');
	$where = defined($where) && length($where) ? " ($where)" : '';
	if (is_exception('cmd_error')) {
		# no additional output
	} elsif (is_exception) {
		print STDERR "ERROR$where: ".exception_message($@)."\n";
	} else {
		print STDERR "UNEXPECTED ERROR$where: $@\n";
	}
}
1;

__END__
