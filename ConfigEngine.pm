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

package ConfigEngine;

use Getopt::Long qw/GetOptionsFromArray/;
use Encode;
use Carp;


use strict;
use warnings;
use utf8;


my @config_opts = qw/key secret region/;

my %deprecations = (
'from-dir'            => 'dir' ,
'to-dir'              => 'dir' ,
'to-vault'            => 'vault',
);
	
my %options = (
'config'              => { type => 's' },
'journal'             => { type => 's', validate => [
	['Journal file not found' => sub { my ($command, $results, $value) = @_;
		if ($command eq 'sync') {
			return 1;
		} else {
			return -r $value;
		}
	},
	'Journal file not writable' => sub { my ($command, $results, $value) = @_;
		if ($command =~ /^(sync|purge\-vault|restore)$/) {
			return (-f $value && -w $value && ! -d $value) || (! -d $value); # TODO: more strict test + actualyy create empty journal file when sync + unit test this
		} else {
			return -r $value;
		}
	},	 ],
] },
	'job-id'             => { type => 's' },
'dir'                 => { type => 's' },
'vault'               => { type => 's' },
'key'                 => { type => 's' },
'secret'              => { type => 's' },
'region'              => { type => 's' },
'concurrency'         => { type => 'i', default => 4, validate => [
	['Max concurrency is 30,  Min is 1' => sub { my ($command, $results, $value) = @_;
		$value >= 1 && $value <= 30
	}],
] },
'partsize'            => { type => 'i', default => 16, validate => [
	['Part size must be power of two'   => sub { my ($command, $results, $value) = @_;
		($value != 0) && (($value & ($value - 1)) == 0)
	}],
] },
'max-number-of-files' => { type => 'i'},
);

my %commands = (
'sync'              => { req => [@config_opts, qw/journal dir vault concurrency partsize/],                 optional => [qw/max-number-of-files/]},
'purge-vault'       => { req => [@config_opts, qw/journal vault concurrency/],                    optional => [qw//], deprecated => [qw/from-dir/] },
'restore'           => { req => [@config_opts, qw/journal dir vault max-number-of-files concurrency/], },
'restore-completed' => { req => [@config_opts, qw/journal vault dir concurrency/],                 optional => [qw//]},
'check-local-hash'  => { req => [@config_opts, qw/journal dir/],                                                      deprecated => [qw/to-vault/] },
	'retrieve-inventory' => { req => [@config_opts, qw/vault/],                 optional => [qw//]},
	'download-inventory' => { req => [@config_opts, qw/vault job-id/],                 optional => [qw//]},
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
	my %reverse_deprecations;
	
	for my $o (keys %deprecations) {
		$reverse_deprecations{ $deprecations{$o} } ||= [];
		push @{ $reverse_deprecations{ $deprecations{$o} } }, $o;
	}

	my $command = shift @argv;
	return (["Please specify command"], undef) unless $command;
	return (undef, undef, 'help', undef) if $command =~ /\bhelp\b/i;
	my $command_ref = $commands{$command};
	return (["Unknown command"], undef) unless $command_ref;
	
	my @getopts;
	for my $o ( @{$command_ref->{req}}, @{$command_ref->{optional}}, @{$command_ref->{deprecated}}, 'config' ) {
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

	my %result; # TODO: deafult hash, config from file
	
	return (["Error parsing options"], @warnings ? \@warnings : undef) unless GetOptionsFromArray(\@argv, \%result, @getopts);
	return (["Extra argument in command line: $argv[0]"], @warnings ? \@warnings : undef) if @argv;
	$result{$_} = decode("UTF-8", $result{$_}, 1) for (keys %result);

	# Special config handling
	#return (["Please specify --config"], @warnings ? \@warnings : undef) unless $result{config};
	
	
	my %source;
	if ($result{config}) {
		my $config_result = $self->read_config($result{config});
		
		my (%merged);
		
		@merged{keys %$config_result} = values %$config_result;
		$source{$_} = 'config' for (keys %$config_result);
	
		@merged{keys %result} = values %result;
		$source{$_} = 'command' for (keys %result);
	
	
		%result =%merged;
	} else {
		$source{$_} = 'command' for (keys %result);
	}
	

	for my $o (keys %deprecations) {
		if ($result{$o}) {
			if (grep { $_ eq $o } @{ $command_ref->{deprecated} }) {
				push @warnings, "$o is not needed for this command";
				delete $result{$o};
			} else {
				if ($result{ $deprecations{$o} } && $source{ $deprecations{$o} } eq 'command') {
					return (["$o specified, while $deprecations{$o} already defined "], @warnings ? \@warnings : undef);
				} else {
					push @warnings, "$o deprecated, use $deprecations{$o} instead";
					$result{ $deprecations{$o} } = delete $result{$o};
				}
			}
		}
	}

	for my $o (@{$command_ref->{req}}) {
		unless ($result{$o}) {
			if (defined($options{$o}->{default})) { # Options from config are used here!
				$result{$o} = $options{$o}->{default};
			} else {
				if (grep { $_ eq $o } @config_opts) {
					return (["Please specify --config with \"$o\" option or --$o"], @warnings ? \@warnings : undef);
				} else {
					return (["Please specify --$o"], @warnings ? \@warnings : undef);
				}
			}
		}
	}
	for my $o (keys %result) {
		if (my $validations = $self->{override_validations}->{$o} || $options{$o}{validate}) {
			for my $v (@$validations) {
				my ($message, $test) = @$v;
				return (["$message"], @warnings ? \@warnings : undef) unless ($test->($command, \%result, $result{$o}));
			}
		}
	}
	

	return (undef, @warnings ? \@warnings : undef, $command, \%result);
}


	
sub read_config
{
	my ($self, $filename) = @_;
	die "config file not found $filename" unless -r $filename; #TODO test
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