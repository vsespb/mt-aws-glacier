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

package App::MtAws::ConfigEngine;

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

our @EXPORT = qw/option options positional command validation message
				mandatory optional seen deprecated validate scope
				present valid value raw_option custom error warning/;
				

our $context; # it's a not a global. always localized in code

# TODOS
#refactor messages %option a% vs %option option%
#options_encoding_error specify source of problem

sub message($;$%)
{
	my ($message, $format, %opts) = @_;
	$format = $message unless defined $format;
	confess "message $message already defined" if defined $context->{messages}->{$message} and !$context->{messages}->{$message}->{allow_redefine};
	$context->{messages}->{$message} = { %opts, format => $format };
	$message;
}


sub new
{
	my ($class, %args) = @_;
	my $self = {
		ConfigOption => 'config',
		%args
	};
	bless $self, $class;
	local $context = $self;
	message 'unexpected_option', 'Unexpected option %option option%', allow_redefine=>1;
	message 'unknown_command', 'Unknown command %command a%', allow_redefine=>1;
	message 'no_command', 'No command specified', allow_redefine=>1;
	message 'deprecated_option', 'Option %option% is deprecated, use %option main% instead', allow_redefine=>1;
	message 'deprecated_command', 'Command %command command% is deprecated', allow_redefine=>1;
	message 'already_specified_in_alias', 'Both options %option a% and %option b% are specified. However they are aliases', allow_redefine=>1;
	message 'getopts_error', 'Error parsing options', allow_redefine=>1;
	message 'options_encoding_error', 'Invalid %encoding% character in command line', allow_redefine => 1;
	message 'cannot_read_config', "Cannot read config file: %config%", allow_redefine => 1;
	message 'mandatory', "Option %option a% is mandatory", allow_redefine => 1;
	message 'positional_mandatory', 'Positional argument #%d n% (%a%) is mandatory', allow_redefine => 1;
	message 'unexpected_argument', "Unexpected argument in command line: %a%", allow_redefine => 1;
	message 'option_deprecated_for_command', "Option %option a% deprecated for this command", allow_redefine => 1;
	return $self;
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
			} elsif (lc $format eq lc 'command') {
				defined(my $value = $data{$name})||confess;
				qq{"$value"};
			} else {
				defined(my $value = $data{$name})||confess;
				sprintf("%$format", $value);
			}
		} else {
			defined(my $value = $data{$match})||confess $spec;
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
			confess qq{message $name not defined} unless $self->{messages}->{$name} and my $format = $self->{messages}->{$name}->{format};
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


sub define($&)
{
	my ($self, $block) = @_;
	local $context = $self; # TODO: create wrapper like 'localize sub ..'
	$block->();
}

sub parse_options
{
	(my $self, local @ARGV) = @_; # we override @ARGV here, cause GetOptionsFromArray is not exported on perl 5.8.8
	
	
	return { command => 'help', map { $_ => undef } qw/errors error_texts warnings warning_texts options/} 
		if (@ARGV && $ARGV[0] =~ /\b(help|h)\b/i);
	
	local $context = $self;
	
	my @getopts = map {
		my $type = defined($_->{type}) ? $_->{type} : 's';
		$type =  "=$type" unless $type eq '';
		map { "$_$type" } $_->{name}, @{ $_->{alias} || [] }, @{ $_->{deprecated} || [] } # TODO: it's possible to implement aliasing using GetOpt itself
	} grep { !$_->{positional} } values %{$self->{options}};
	
	error('getopts_error') unless GetOptions(\my %results, @getopts);
	
	unless ($self->{errors}) {
		for (sort keys %results) { # sort needed here to define a/b order for already_specified_in_alias 
			my ($optref, $is_alias);
			if ($self->{options}->{$_}) {
				($optref, $is_alias) = ($self->{options}->{$_}, 0);
			} else {
				($optref, $is_alias) = (($self->{options}->{ $self->{optaliasmap}->{$_} } || confess "unknown option $_"), 1);
				warning('deprecated_option', option => $_, main => $self->{optaliasmap}->{$_}) if $self->{deprecated_options}->{$_};
			}
			
			error('already_specified_in_alias', a => $optref->{original_option}, b => $_) if ((defined $optref->{value}) && $optref->{source} eq 'option');
			
			# fill from options from command line
			unless (defined eval {
				@{$optref}{qw/value source original_option is_alias/} =
					(decode("UTF-8", $results{$_}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC), 'option', $_, $is_alias);
			}) {
				error("options_encoding_error", encoding => 'UTF-8');
				last;
			}
		}
	}
	
	
	my $command = undef;
	
	unless ($self->{errors}) {
		my $original_command = $command = shift @ARGV;
		if (defined($command)) {
			error("unknown_command", a => $original_command) unless
				$self->{commands}->{$command} ||
				(defined($command = $self->{aliasmap}->{$command}) && $self->{commands}->{$command}); 
			warning('deprecated_command', command => $original_command) if ($self->{deprecated_commands}->{$original_command});
		} else {
			error("no_command") unless defined $command;
		}
	}
	
	unless ($self->{errors}) {
		$self->{positional_tail} = \@ARGV;
	}
	
	unless ($self->{errors}) {
		my $cfg_opt = undef;
		if (defined($self->{ConfigOption}) and $cfg_opt = $self->{options}->{$self->{ConfigOption}}) {
			my $cfg_value = $cfg_opt->{value};
			$cfg_value = $cfg_opt->{default} unless defined $cfg_value;
			if (defined $cfg_value) { # we should also check that config is 'seen'. we can only check below (so it must be seen)
				my $cfg = $self->read_config($cfg_value);
				if (defined $cfg) {
					for (keys %$cfg) {
						my $optref = $self->{options}->{$_};
						unless (defined $optref->{value}) {
							# fill from config
							@{$optref}{qw/value source/} = ($cfg->{$_}, 'config');
						}
					}
				} else {
					error("cannot_read_config", config => $cfg_value);
				}
			}
		}
		
		for (values %{$self->{options}}) {
			# fill from default values
			@{$_}{qw/value source/} = ($_->{default}, 'default') if (!defined($_->{value}) && defined($_->{default}));#$_->{seen} && 
		}
		 
		$self->{commands}->{$command}->{cb}->(); # the callback!
		
		if ($cfg_opt) {
			confess "Config (option '$self->{ConfigOption}') must be seen" unless $cfg_opt->{seen};
		}
		
		for (values %{$self->{options}}) {
			error('unexpected_option', option => _real_option_name($_)) if defined($_->{value}) && ($_->{source} eq 'option') && !$_->{seen}; # TODO: test validation same way
		}
		
		unless ($self->{errors}) {
			if (@ARGV) {
				unless (defined eval {
					error('unexpected_argument', a => decode("UTF-8", shift @ARGV, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)); 1;
				}) {
					error("options_encoding_error", encoding => 'UTF-8');
				}
			}
		}
		
		unless ($self->{errors}) {
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
		if ($v->{seen} && defined($v->{value})) {
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

sub option($;%) {
	my ($name, %opts) = @_;
	confess "option already declared" if $context->{options}->{$name};
	if (%opts) {
		
		if (defined $opts{alias}) {
			$opts{alias} = [$opts{alias}] if ref $opts{alias} eq ref ''; # TODO: common code for two subs, move out
		}
		
		if (defined $opts{deprecated}) {
			$opts{deprecated} = [$opts{deprecated}] if ref $opts{deprecated} eq ref '';
		}
		
		for (@{$opts{alias}||[]}, @{$opts{deprecated}||[]}) {
			confess "option $_ already declared" if defined $context->{options}->{$_};
			confess "alias $_ already declared" if defined $context->{optaliasmap}->{$_};
			$context->{optaliasmap}->{$_} = $name;
		}
		
		$context->{deprecated_options}->{$_} = 1 for (@{$opts{deprecated}||[]});
	}
	$context->{options}->{$name} = { %opts, name => $name } unless $context->{options}->{$name};
	return $name;
};

sub positional($;%)
{
	option shift, @_, positional => 1;
}

sub options(@) {
	map {
		confess "option already declared $_" if $context->{options}->{$_};
		$context->{options}->{$_} = { name => $_ };
		$_
	} @_;
};


sub validation(@_)
{
	my ($name, $message, $cb, %opts) = (shift, shift, pop @_, @_);
	confess "undeclared option" unless defined $context->{options}->{$name};
	push @{ $context->{options}->{$name}->{validations} }, {  %opts, 'message' => $message, cb => $cb }
		unless $context->{override_validations} && exists($context->{override_validations}->{$name});
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

sub _real_option_name($)
{
	my ($opt) = @_;
	defined($opt->{original_option}) ? $opt->{original_option} : $opt->{name};
}

sub seen
{
	my $o = @_ ? shift : $_;
	my $option = $context->{options}->{$o} or confess "undeclared option $o";
	unless ($option->{seen}) {
		$option->{seen} = 1;
		if ($option->{positional}) {
			my $v = shift @{$context->{positional_tail}};
			if (defined $v) {
				push @{$context->{positional_backlog}}, $o;
				unless (defined eval {
					@{$option}{qw/value source/} = (decode("UTF-8", $v, Encode::DIE_ON_ERR|Encode::LEAVE_SRC), 'positional');
				}) {
					error("options_encoding_error", encoding => 'UTF-8');
				}
			}
		}
	}
	$o;
}

sub mandatory(@) {
	return map {
		my $opt = assert_option;
		unless ($opt->{seen}) {
			seen;
			confess "mandatory positional argument goes after optional one"
				if ($opt->{positional} and ($context->{positional_level} ||= 'mandatory') ne 'mandatory');
			unless (defined($opt->{value})) {
				$opt->{positional} ?
					error("positional_mandatory", a => $_, n => scalar @{$context->{positional_backlog}||[]}+1) :
					error("mandatory", a => _real_option_name($opt)); # actually does not have much sense
			}
		}
		$_;
	} @_;
};

sub optional(@)
{
	return map {
		seen;
		$context->{positional_level} = 'optional' if ($context->{options}->{$_}->{positional});
		$_;
	} @_;
};

sub deprecated(@)
{
	return map {
		assert_option;
		my $opt = $context->{options}->{ seen() };
		confess "positional options can't be deprecated" if $opt->{positional};
		if (defined $opt->{value}) {
			warning('option_deprecated_for_command', a => _real_option_name $opt);
			undef $opt->{value};
		}
		$_;
	} @_;
};
sub validate(@)
{
	return map {
		my $opt = $context->{options}->{seen()};
		if (defined($opt->{value}) && !$opt->{validated}) {
			$opt->{validated} = $opt->{valid} = 1;
			VALIDATION: for my $v (@{ $opt->{validations} }) {
				for ($opt->{value}) {
					error ({ format => $v->{message}, a => _real_option_name $opt}),
					$opt->{valid} = 0,
					$v->{stop} && last VALIDATION
						unless $v->{cb}->();
				}
			}
		};
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

sub present(@) # TODO: test that it works with arrays
{
	my ($name) = @_;
	assert_option for $name;
	return defined($context->{options}->{$name}->{value})
};

sub valid($)
{
	my ($name) = @_;
	assert_option for $name;
	confess "validation not performed yet" unless $context->{options}->{$name}->{validated};
	return $context->{options}->{$name}->{valid};
};

sub value($)
{
	my ($name) = @_;
	assert_option for $name;
	confess "option not present" unless defined($context->{options}->{$name}->{value});
	return $context->{options}->{$name}->{value};
};

sub raw_option($)
{
	my ($name) = @_;
	assert_option for $name;
	confess "option not present" unless defined($context->{options}->{$name}->{value});
	return $context->{options}->{$name};
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





