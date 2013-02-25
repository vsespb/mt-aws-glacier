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

use constant DEPRECATED_OPTION => "deprecated_option";
use constant DEPRECATED_COMMAND => "deprecated_command";
use constant ALREADY_SPECIFIED_IN_ALIAS => 'already_specified_in_alias';

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
	my $self = {
		ConfigOption => 'config',
		%args
	};
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

sub require_message($)
{
	my ($name) = @_;
	confess "message $name not declared" unless defined $context->{messages}->{$name};
	$name;
}

sub arrayref_or_undef($)
{
	my ($ref) = @_;
	defined($ref) && @$ref > 0 ? $ref : undef;
}


sub message($;$)
{
	my ($message, $format) = @_;
	$format = $message unless defined $format;
	confess "message $message already defined" if defined $context->{messages}->{$message};
	$context->{messages}->{$message} = $format;
	$message;
}

sub parse_options
{
	(my $self, local @ARGV) = @_; # we override @ARGV here, cause GetOptionsFromArray is not exported on perl 5.8.8
	
	local $context = $self;
	
	my @getopts = map {
		map { "$_=s" } $_->{name}, @{ $_->{alias} || [] }, @{ $_->{deprecated} || [] }
	} values %{$self->{options}};
	GetOptions(\my %results, @getopts);
	
	message 'unexpected_option', 'Unexpected option %option option%';
	for (sort keys %results) { # sort needed here to define a/b order for already_specified_in_alias 
		my ($optref, $is_alias);
		if ($self->{options}->{$_}) {
			($optref, $is_alias) = ($self->{options}->{$_}, 0);
		} else {
			($optref, $is_alias) = (($self->{options}->{ $self->{optaliasmap}->{$_} } || confess "unknown option $_"), 1);
			warning(DEPRECATED_OPTION, option => $_) if $self->{deprecated_options}->{$_};
		}
		
		error(ALREADY_SPECIFIED_IN_ALIAS, a => $optref->{original_option}, b => $_) if ((defined $optref->{value}) && $optref->{source} eq 'option');
		
		# fill from options from command line
		@{$optref}{qw/value source original_option is_alias/} = ($results{$_}, 'option', $_, $is_alias);
	}
	
	
	my $command = undef;
	unless ($self->{errors}) {
		my $original_command = $command = shift @ARGV;
		confess "no command specified" unless defined $command;
		confess "unknown command or alias" unless
			$self->{commands}->{$command} ||
			(defined($command = $self->{aliasmap}->{$command}) && $self->{commands}->{$command}); 
		 
		my $cfg_opt = undef;
		if (defined($self->{ConfigOption}) and $cfg_opt = $self->{options}->{$self->{ConfigOption}}) {
			my $cfg_value = $cfg_opt->{value};
			$cfg_value = $cfg_opt->{default} unless defined $cfg_value;
			if (defined $cfg_value) {
				my $cfg = $self->read_config($cfg_opt->{value});
				for (keys %$cfg) {
					my $optref = $self->{options}->{$_};
					unless (defined $optref->{value}) {
						# fill from config
						@{$optref}{qw/value source/} = ($cfg->{$_}, 'config');
					}
				}
			}
		}
		
		for (values %{$self->{options}}) {
			# fill from default values
			@{$_}{qw/value source/} = ($_->{default}, 'default') if (!defined($_->{value}) && defined($_->{default}));#$_->{seen} && 
		}
		 
		$self->{commands}->{$command}->{cb}->();
		
		if ($cfg_opt) {
			confess "Config (option '$self->{ConfigOption}') must be seen" unless $cfg_opt->{seen};
		}
		
		for (values %{$self->{options}}) {
			error('unexpected_option', option => $_->{name}) if defined($_->{value}) && ($_->{source} eq 'option') && !$_->{seen};
		}
		unless ($self->{errors}) {
			warning(DEPRECATED_COMMAND, command => $original_command) if ($self->{deprecated_commands}->{$original_command});
			$self->unflatten_scope();
		}
	}
		
	$self->{error_texts} = [ $self->errors_or_warnings_to_messages($self->{errors}) ];
	$self->{warning_texts} = [ $self->errors_or_warnings_to_messages($self->{warnings}) ];
	
	return {
		errors => arrayref_or_undef $self->{errors},
		error_texts => arrayref_or_undef $self->{error_texts},
		warnings => arrayref_or_undef $self->{warnings},
		warning_texts => arrayref_or_undef $self->{warning_texts},
		command => $self->{errors} ? undef : $command,
		options => $self->{data}
	};
}

sub unflatten_scope
{
	my ($self) = @_;
	my $options = {};
	for my $k (keys %{$self->{options}}) {
		my $v = $self->{options}->{$k};
		if ($v->{seen}) {
			my $dest = $options;
			for (@{$v->{scope}||[]}) {
				$dest = $dest->{$_} ||= {};
			}
			$dest->{$k} = $v->{value};
		}
	}
	$self->{data} = $options;
}


sub assert_option { $context->{options}->{$_} or confess "undeclared option $_"; }

#TODO: die if redefining options??
sub option($;%) {
	my ($name, %opts) = @_;
	confess "option already declared" if $context->{options}->{$name};
	if (%opts) {
		
		if (defined $opts{alias}) {
			require_message(ALREADY_SPECIFIED_IN_ALIAS);
			$opts{alias} = [$opts{alias}] if ref $opts{alias} eq ref ''; # TODO: common code for two subs, move out
		}
		
		if (defined $opts{deprecated}) {
			require_message(DEPRECATED_OPTION);
			require_message(ALREADY_SPECIFIED_IN_ALIAS);
			$opts{deprecated} = [$opts{deprecated}] if ref $opts{deprecated} eq ref '';
		}
		
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
	map {
		confess "option already declared" if $context->{options}->{$_};
		$context->{options}->{$_} = { name => $_ };
		$_
	} @_;
};


sub validation($$&)
{
	my ($name, $message, $cb) = @_;
	confess "undeclared option" unless defined $context->{options}->{$name};
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
		
		require_message(DEPRECATED_COMMAND) if defined $opts{deprecated};
		
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
			error("mandatory", a => $_) unless defined($context->{options}->{$_}->{value});
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
	$context->{options}->{$name} = {source => 'set', value => $value, name => $name, seen => 1 };
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
	
sub read_config
{
	my ($self, $filename) = @_;
	return unless -f $filename && -r $filename; #TODO test
	open (my $F, "<:crlf:encoding(UTF-8)", $filename) || return;
	my %newconfig;
	while (<$F>) {
		chomp;
		next if /^\s*$/;
		next if /^\s*\#/;
		/^([^=]+)=(.*)$/;
		my ($name, $value) = ($1,$2); # TODO: test lines with wrong format
		$name =~ s/^[ \t]*//;
		$name =~ s/[ \t]*$//;
		$value =~ s/^[ \t]*//;
		$value =~ s/[ \t]*$//;
		$newconfig{$name} = $value;
	}
	close $F;
	return \%newconfig;
}

1;





