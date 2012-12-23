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

package ConfigEngine;

use Getopt::Long qw/GetOptionsFromArray/;
use Carp;


use strict;
use warnings;
use utf8;

	
my %options = (
'config'              => { },
'from-dir'            => { deprecated_in_favour => 'dir' },
'dir'                 => { },
'vault'               => { },
'to-vault'            => { deprecated_in_favour => 'vault' },
'journal'             => { },
'concurrency'         => { type => 'i', validate => [ ['Max concurrency is 10,  Min is 1' => sub { $_ >= 1 && $_ <= 10 }],  ] },
'partsize'            => { type => 'i', validate => [ ['Part size must be power of two'   => sub { ($_ != 0) && (($_ & ($_ - 1)) == 0)}], ] },
'max-number-of-files' => { type => 'i'},
);

my %commands = (
'sync'              => { req => [qw/config journal dir vault/],                optional => [qw/partsize concurrency max-number-of-files/]},
'purge-vault'       => { req => [qw/config journal vault/],                     optional => [qw/concurrency/] },
'restore'           => { req => [qw/config journal vault max-number-of-files/]},
'restore-completed' => { req => [qw/config journal vault max-number-of-files/]},
'check-local-hash'  => { req => [qw/config journal to-vault/] },
);


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	return $self;
}



sub parse_options
{
	my ($self, @argv) = (@_);

	my (@warnings);
	my %deprecation;
	
	for my $o (keys %options) {
		if ($options{$o}->{deprecated_in_favour}) {
			$deprecation{ $options{$o}->{deprecated_in_favour} } ||= [];
			push @{ $deprecation{ $options{$o}->{deprecated_in_favour} } }, $o;
		}
	}

	my $command = shift @argv;
	my $command_ref = $commands{$command};
	
	my @getopts;
	for my $o ( @{$command_ref->{req}}, @{$command_ref->{optional}} ) {
		my $option = $options{$o};
		my $type = $option->{type}||'s';
		my $opt_spec = join ('|', $option->{spec}||$o, @{ $option->{alias}||[] });
		push @getopts, "$opt_spec=$type";
		
		if ($deprecation{$o}) {
			for my $dep_o (@{ $deprecation{$o} }) {
				my $dep_option= $options{$dep_o};
				my $type = $dep_option->{type}||'s';
				my $opt_spec = join ('|', $dep_option->{spec}||$dep_o, @{ $dep_option->{alias}||[] });
				push @getopts, "$opt_spec=$type";
			}
		}
	}

	my %result; # TODO: deafult hash, config from file
	
	return (["Error parsing options"], \@warnings, undef) unless GetOptionsFromArray(\@argv, \%result, @getopts);


	for my $o (keys %options) {
		if ($options{$o}->{deprecated_in_favour} && $result{$o}) {
			push @warnings, "$o deprecated, use $options{$o}->{deprecated_in_favour} instead";
			if ($result{ $options{$o}->{deprecated_in_favour} }) {
				return (["$o specified, while $options{$o}->{deprecated_in_favour} already defined"], \@warnings, undef);
			} else {
				$result{ $options{$o}->{deprecated_in_favour} } = delete $result{$o};
			}
		}
	}

	for my $o (@{$command_ref->{req}}) {
		return (["Please specify $o"], \@warnings, undef) unless $result{$o};
	}

	for my $o (keys %result) {
		if (my $validations = $options{$o}{validate}) {
			for my $v (@$validations) {
				my ($message, $test) = @$v;
				$_ = $result{$o};
				return (["$message"], \@warnings, undef) unless ($test->());
			}
		}
	}
	
	return (undef, \@warnings, \%result);
}
	
1;