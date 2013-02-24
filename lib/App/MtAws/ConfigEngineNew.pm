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

package App::MtAws::ConfigEngineNew;

use Getopt::Long;
use Encode;
use Carp;
use List::Util qw/first/;

use strict;
use warnings;
use utf8;
			use Data::Dumper;
require Exporter;                                                                                                                                                                                                                                                              
use base qw/Exporter/;                                                                                                                                                                                                                                                         
                                                                                                                                                                                                                                                                               
our @EXPORT = qw/option options command validation message
				mandatory optional validate scope
				present custom error warning/;
				

our $context; 

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	return $self;
}

sub define($&)
{
	my ($self, $block) = @_;
	local $context = $self;
	$block->();
}

sub error_to_message
{
	my ($spec, %data) = @_;
	my $rep = sub {
		my ($match) = @_;
		if (my ($format, $name) = $match =~ /^([\w]+)\s+([\w]+)$/) {
			if (lc $format eq lc 'option') {
				defined(my $value = $data{$name})||confess;
				qq{"--$value"};
			} else {
				defined(my $value = $data{$name})||confess;
				sprintf("%$format", $value);
			}
		} else {
			defined(my $value = $data{$match})||confess;
			$value;
		}
	};
	
	$spec =~ s{%([\w\s]+)%} {$rep->($1)}ge if %data; # in new perl versions \w also means unicode chars..
	$spec;
}


sub errors_or_warnings_to_messages
{
	my ($self, $err) = @_;
	return unless defined $err;
	map {
		if (ref($_) eq ref({})) {
			my $name = $_->{format} || confess "format not defined";
			confess qq{message $name not defined} unless my $format = $self->{messages}->{$name};
			error_to_message($format, %$_);
		} else {
			$_;
		}
	} @{$err};
}

sub arrayref_or_undef($)
{
	my ($ref) = @_;
	defined($ref) && @$ref > 0 ? $ref : undef;
}

sub parse_options
{
	(my $self, local @ARGV) = @_; # we override @ARGV here, cause GetOptionsFromArray is not exported on perl 5.8.8
	
	local $context = $self;
	
	my @getopts = map {
		map { "$_=s" } $_->{name}, @{ $_->{alias} || [] }, @{ $_->{deprecated} || [] }
	} values %{$self->{options}};
	GetOptions(\my %results, @getopts);
	
	for (keys %results) {
		my $optref;
		if ($self->{options}->{$_}) {
			$optref = $self->{options}->{$_};
		} else {
			$optref = $self->{options}->{ $self->{optaliasmap}->{$_} } || confess "unknown option $_";
			warning("deprecated_option", option => $_) if $self->{deprecated_options}->{$_};
		}
		@{$optref}{qw/value source original_option/} = ($results{$_}, 'option', $_);
	}
	
	my $original_command = my $command = shift @ARGV;
	confess "unknown command or alias" unless
		$self->{commands}->{$command} ||
		(defined($command = $self->{aliasmap}->{$command}) && $self->{commands}->{$command}); 
	 
	$self->{commands}->{$command}->{cb}->();
	
	$self->unflatten_scope();
	
	$self->{error_texts} = [ $self->errors_or_warnings_to_messages($self->{errors}) ];
	
	warning('deprecated_command', command => $original_command) if ($self->{deprecated_commands}->{$original_command});

	
	$self->{warning_texts} = [ $self->errors_or_warnings_to_messages($self->{warnings}) ];	
	
	return {
		errors => arrayref_or_undef $self->{errors},
		error_texts => arrayref_or_undef $self->{error_texts},
		warnings => arrayref_or_undef $self->{warnings},
		warning_texts => arrayref_or_undef $self->{warning_texts},
		command => $command,
		options => $self->{data}
	};
}

sub unflatten_scope
{
	my ($self) = @_;
	my $options = {};
	for my $k (keys %{$self->{options}}) {
		my $v = $self->{options}->{$k};
		my $dest = $options;
		for (@{$v->{scope}||[]}) {
			$dest = $dest->{$_} ||= {};
		}
		$dest->{$k} = $v->{value};
	}
	$self->{data} = $options;
}


sub assert_option { $context->{options}->{$_} or confess "undeclared option $_"; }

#TODO: die if redefining options??
sub option($;%) {
	my ($name, %opts) = @_;
	if (%opts) {
		$opts{alias} = [$opts{alias}] if (defined $opts{alias}) && (ref $opts{alias} eq ref ''); # TODO: common code for two subs, move out
		$opts{deprecated} = [$opts{deprecated}] if (defined $opts{deprecated}) && ref $opts{deprecated} eq ref '';
		
		
		for (@{$opts{alias}||[]}, @{$opts{deprecated}||[]}) {
			confess "option $_ already declared" if defined $context->{options}->{$_};
			confess "alias $_ already declared" if defined $context->{optaliasmap}->{$_};
			$context->{optaliasmap}->{$_} = $name;
		}
		
		$context->{deprecated_options}->{$_} = 1 for (@{$opts{deprecated}||[]});
	}
	$context->{options}->{$name} = { name => $name, %opts } unless $context->{options}->{$name};
	return $name;
};

sub options(@) {
	map { $context->{options}->{$_} = { name => $_ } unless $context->{options}->{$_}; $_	} @_
};

sub message($$)
{
	my ($message, $format) = @_;
	confess if defined $context->{messages}->{$message};
	$context->{messages}->{$message} = $format;
	$message;
}

sub validation($$&)
{
	my ($name, $message, $cb) = @_;
	option($name);
	push @{ $context->{options}->{$name}->{validations} }, { 'message' => $message, cb => $cb };
	$name;
}

sub command($%;$)
{
	my ($name, $cb, %opts) = (shift, pop, @_); # firs arg is name, last is cb, optional middle is opt

	confess "command $name already declared" if defined $context->{commands}->{$name};
	confess "alias $name already declared" if defined $context->{aliasmap}->{$name};
	if (%opts) {
		$opts{alias} = [$opts{alias}] if (defined $opts{alias}) && (ref $opts{alias} eq ref '');
		$opts{deprecated} = [$opts{deprecated}] if (defined $opts{deprecated}) && ref $opts{deprecated} eq ref '';
		
		for (@{$opts{alias}||[]}, @{$opts{deprecated}||[]}) {
			confess "command $_ already declared" if defined $context->{commands}->{$_};
			confess "alias $_ already declared" if defined $context->{aliasmap}->{$_};
			$context->{aliasmap}->{$_} = $name;
		}

		$context->{deprecated_commands}->{$_} = 1 for (@{$opts{deprecated}||[]});
	}
	$context->{commands}->{$name} = { cb => $cb, %opts };
	return;
};

sub mandatory(@) {
	return map {
		assert_option;
		unless ($context->{options}->{$_}->{seen}) {
			$context->{options}->{$_}->{seen} = 1;
			push @{$context->{errors}}, { format => "mandatory", a => $_ } unless defined($context->{options}->{$_}->{value});
		}
		$_;
	} @_;
};

sub optional(@)
{
	return map {
		assert_option;
		$context->{options}->{$_}->{seen} = 1;
		$_;
	} @_;
};

sub validate(@)
{
	return map {
		assert_option;
		my $option = $_;
		my $optionref = $context->{options}->{$option};
		$optionref->{seen} = 1;
		for my $v (@{ $optionref->{validations} }) {
			for ($optionref->{value}) {
				error ({ format => $v->{message}, a => $option}) unless $v->{cb}->();
			}
		}
		$_;
	} @_;
};

sub scope($@)
{
	my $scopename = shift; 
	return map {
		assert_option;
		unshift @{$context->{options}->{$_}->{scope}}, $scopename;
		$_;
	} @_;
};

sub present($)
{
	my ($name) = @_;
	assert_option for $name;
	return defined($context->{options}->{$name}->{value})
};

sub custom($$)
{
	my ($name, $value) = @_;
	confess if ($context->{options}->{$name});
	$context->{options}->{$name} = {source => 'set', value => $value, name => $name };
	return $name;
};


sub error($;%)
{
	my ($name, %data) = @_;
	push @{$context->{errors}},
		defined($context->{messages}->{$name}) ?
			{ format => $name, %data } :
			(%data ? confess("message '$name' is undefined") : $name);
	return;
};
	
sub warning($;%)
{
	my ($name, %data) = @_;
	push @{$context->{warnings}},
		defined($context->{messages}->{$name}) ?
			{ format => $name, %data } :
			(%data ? confess("message '$name' is undefined") : $name);
	return;
};
	


1;





