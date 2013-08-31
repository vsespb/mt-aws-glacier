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

our $VERSION = '1.050';

use strict;
use warnings;
use utf8;
use Encode;
use constant BINARY_ENCODING => "MT_BINARY";
use App::MtAws::Utils;

use Carp;
eval { require I18N::Langinfo; }; # TODO: test that it's loaded compile time, test that it wont break if failed

require Exporter;
use base qw/Exporter/;


our @EXPORT = qw/exception get_exception is_exception exception_message dump_error get_errno/;

our $_errno_encoding = undef;

sub get_errno
{
	my $err = "$_[0]";
	local ($@, $!);

	# some code in this scope copied from Encode::Locale
	# http://search.cpan.org/perldoc?Encode%3A%3ALocale
	# by Gisle Aas <gisle@aas.no>.
	$_errno_encoding ||= eval {
		require I18N::Langinfo;
		my $enc = I18N::Langinfo::langinfo(I18N::Langinfo::CODESET());
		# copy-paste workaround from Encode::Locale
		# https://rt.cpan.org/Ticket/Display.html?id=66373
		$enc = "hp-roman8" if $^O eq "hpux" && $enc eq "roman8";

		defined (find_encoding($enc)) ? $enc : undef;
	} || BINARY_ENCODING();

	my $res;
	if ($_errno_encoding eq BINARY_ENCODING) {
		$res = hex_dump_string($err);
	} else {
		eval {
			# workaround issue https://rt.perl.org/rt3/Ticket/Display.html?id=119499
			# perhaps Encode::decode_utf8 can be used here too
			$res = utf8::is_utf8($err) ? $err : decode($_errno_encoding, $err, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
			1;
		} or do {
			$res = hex_dump_string($err);
		}
	}
	$res;
}

# Does not work with directory names

# exception [$previous] { $msg | $code => $msg } name1 => value1, name2 => value2 ...
# exception [$previous] { $msg | $code => $msg } name1 => value1, 'ERRNO', name2 => value2 ...
sub exception
{
	my %data;
	%data = %{shift()} if (ref $_[0] eq ref {});
	if (scalar @_ == 1) {
		$data{message} = shift;
	} else {
		@data{qw/code message/} = (shift, shift);
		while (@_) {
			my $key = shift;
			if ($key eq 'ERRNO') {
				confess "ERRNO already used" if exists $data{'errno'};
				$data{'errno'} = get_errno($!);
				$data{'errno_code'} = $!+0; # numify
			} else {
				$data{$key} = shift or confess "Malformed exception"
			}
		}
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
