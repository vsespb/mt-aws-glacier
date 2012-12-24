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
use Encode;
use Carp;


use strict;
use warnings;
use utf8;


my %deprecations = (
'from-dir'            => 'dir' ,
'to-dir'              => 'dir' ,
'to-vault'            => 'vault',
);
	
my %options = (
'config'              => { type => 's' },
'journal'             => { type => 's' }, #validate => [ ['Journal file not exist' => sub {-r } ], ]
'dir'                 => { type => 's' },
'vault'               => { type => 's' },
'concurrency'         => { type => 'i', validate => [ ['Max concurrency is 10,  Min is 1' => sub { $_ >= 1 && $_ <= 10 }],  ] },
'partsize'            => { type => 'i', validate => [ ['Part size must be power of two'   => sub { ($_ != 0) && (($_ & ($_ - 1)) == 0)}], ] },
'max-number-of-files' => { type => 'i'},
);

# TODO: from-dir is optional, it warns that dir should be used. however from-dir is deprecated for this command!
# TODO: deprecated options should be removed from result
my %commands = (
'sync'              => { req => [qw/config journal dir vault/],                 optional => [qw/partsize concurrency max-number-of-files/]},
'purge-vault'       => { req => [qw/config journal vault /],                    optional => [qw/concurrency/], deprecated => [qw/from-dir/] },
'restore'           => { req => [qw/config journal dir vault max-number-of-files/], },
'restore-completed' => { req => [qw/config journal vault dir/],                 optional => [qw/concurrency/]},
'check-local-hash'  => { req => [qw/config journal dir/],                                                      deprecated => [qw/to-vault/] },
);


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	return $self;
}


sub get_options_and_config
{
	my ($self, @argv) = (@_);
	my ($errors, $warnings, $result) = $self->{parse_options};

	for (@$warnings) {
		warn "WARNING: $_";;
	}	
	if ($errors) {
		die $errors->[0];
	}
	
	$result->{config};
}

sub parse_options
{
	my ($self, @argv) = (@_);

	my (@warnings);
	my %reverse_deprecations;
	
	for my $o (keys %deprecations) {
		$reverse_deprecations{ $deprecations{$o} } ||= [];
		push @{ $reverse_deprecations{ $deprecations{$o} } }, $o;
	}

	my $command = shift @argv;
	my $command_ref = $commands{$command};
	
	my @getopts;
	for my $o ( @{$command_ref->{req}}, @{$command_ref->{optional}}, @{$command_ref->{deprecated}} ) {
		my $option = $options{$o};
		my $type = $option->{type}||'s';
		my $opt_spec = join ('|', $o, @{ $option->{alias}||[] });
		push @getopts, "$opt_spec=$type";
		
		if ($reverse_deprecations{$o}) {
			my $type = $option->{type}||'s';
			for my $dep_o (@{ $reverse_deprecations{$o} }) {
				push @getopts, "$dep_o=$type";
			}
		}
	}

	#die join(';',@getopts);
	my %result; # TODO: deafult hash, config from file
	
	return (["Error parsing options"], @warnings ? \@warnings : undef) unless GetOptionsFromArray(\@argv, \%result, @getopts);
	$result{$_} = decode("UTF-8", $result{$_}, 1) for (keys %result);

	# Special config handling
	return (["Please specify config"], @warnings ? \@warnings : undef) unless $result{config};
	
	
	my $config_result = $self->read_config($result{config});
	my %merged = %$config_result;
	@merged{keys %result} = values %result;
	%result = %merged;
	

	#use Data::Dumper;print Dumper(\%result);

	for my $o (keys %deprecations) {
		if ($result{$o}) {
			if (grep { $_ eq $o } @{ $command_ref->{deprecated} }) {
				push @warnings, "$o is not needed for this command";
				delete $result{$o};
			} else {
				if ($result{ $deprecations{$o} }) {
					return (["$o specified, while $deprecations{$o} already defined"], @warnings ? \@warnings : undef);
				} else {
					push @warnings, "$o deprecated, use $deprecations{$o} instead";
					$result{ $deprecations{$o} } = delete $result{$o};
				}
			}
		}
	}

	for my $o (@{$command_ref->{req}}) {
		return (["Please specify $o"], @warnings ? \@warnings : undef) unless $result{$o};
	}

	for my $o (keys %result) {
		if (my $validations = $options{$o}{validate}) {
			for my $v (@$validations) {
				my ($message, $test) = @$v;
				$_ = $result{$o};
				return (["$message"], @warnings ? \@warnings : undef) unless ($test->());
			}
		}
	}
	
	return (undef, @warnings ? \@warnings : undef, $command, \%result);
}
	
sub read_config
{
	my ($self, $filename) = @_;
	die "config file not found $filename" unless -f $filename;
	open (F, "<:encoding(UTF-8)", $filename);
	my %newconfig;
	while (<F>) {
		chomp;
		chop if /\r$/; # windows CRLF format
		next if /^\s*$/;
		next if /^\s*\#/;
		my ($name, $value) = split(/\=/, $_);
		$name =~ s/^\s*//;
		$name =~ s/\s*$//;
		$value =~ s/^\s*//;
		$value =~ s/\s*$//;
		
		$newconfig{$name} = $value;
	}
	close F;
	return \%newconfig;
}

1;