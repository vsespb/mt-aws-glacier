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

use Getopt::Long 2.24 qw/:config no_ignore_case/ ;
use Encode;
use Carp;
use List::Util qw/first/;
use strict;
use warnings;
use utf8;

require Exporter;
use base qw/Exporter/;

our @EXPORT = qw/option options positional command validation message
				mandatory optional seen deprecated validate scope
				present valid value lists raw_option custom error warning impose explicit/;

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
		%args
	};
	bless $self, $class;
	local $context = $self;
	# TODO: replace "%s option% with "%option%" - will this work?
	message 'list_options_in_config', '"List" options (where order is important) like "%s option%" cannot appear in config currently', allow_redefine => 1;
	message 'unexpected_option', 'Unexpected option %option option%', allow_redefine=>1;
	message 'unknown_config_option', 'Unknown option in config: "%s option%"', allow_redefine=>1;
	message 'unknown_command', 'Unknown command %command a%', allow_redefine=>1;
	message 'no_command', 'No command specified', allow_redefine=>1;
	message 'deprecated_option', 'Option %option% is deprecated, use %option main% instead', allow_redefine=>1;
	message 'deprecated_command', 'Command %command command% is deprecated', allow_redefine=>1;
	message 'already_specified_in_alias', 'Both options %option a% and %option b% are specified. However they are aliases', allow_redefine=>1;
	message 'getopts_error', 'Error parsing options', allow_redefine=>1;
	message 'options_encoding_error', 'Invalid %encoding% character in command line', allow_redefine => 1;
	message 'config_encoding_error', 'Invalid %encoding% character in config file', allow_redefine => 1;
	message 'cannot_read_config', "Cannot read config file: %config%", allow_redefine => 1;
	message 'mandatory', "Option %option a% is mandatory", allow_redefine => 1;
	message 'positional_mandatory', 'Positional argument #%d n% (%a%) is mandatory', allow_redefine => 1;
	message 'unexpected_argument', "Unexpected argument in command line: %a%", allow_redefine => 1;
	message 'option_deprecated_for_command', "Option %option a% deprecated for this command", allow_redefine => 1;
	message 'unknown_encoding', 'Unknown encoding "%s value%" in option %option a%', allow_redefine => 1;
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

sub decode_option_value
{
	my ($self, $val) = @_;
	my $enc = $self->{cmd_encoding}||confess;
	my $decoded = eval {decode($enc, $val, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)};
	error("options_encoding_error", encoding => $enc) unless defined $decoded;
	$decoded;
}

sub decode_config_value
{
	my ($self, $val) = @_;
	my $enc = $self->{cfg_encoding}||confess;
	my $decoded = eval {decode($enc, $val, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)};
	error("config_encoding_error", encoding => $enc) unless defined $decoded;
	$decoded;
}

sub get_encoding
{
	my ($name, $config, $options) = @_;
	return undef unless defined $name;
	my $res = undef;

	if (defined $config && defined($config->{$name})) {
		my $new_enc_obj = find_encoding($config->{$name});
		error('unknown_encoding', encoding => $config->{$name}, a => $name), return unless $new_enc_obj;
		$res = $new_enc_obj;
	}

	my $new_encoding = first { $_->{name} eq $name } @$options;
	if (defined $new_encoding && defined $new_encoding->{value}) {
		my $new_enc_obj = find_encoding($new_encoding->{value});
		error('unknown_encoding', encoding => $new_encoding->{value}, a => $name), return unless $new_enc_obj;
		$res = $new_enc_obj;
	}

	$res
}

sub get_option_ref
{
	my ($self, $name) = @_;
	if ($self->{options}->{$name}) {
		return ($self->{options}->{$name}, 0);
	} elsif (defined($self->{optaliasmap}->{$name})) {
		return ($self->{options}->{ $self->{optaliasmap}->{$name} }, 1);
	} else {
		return (undef, undef);
	}
}

sub parse_options
{
	(my $self, local @ARGV) = @_; # we override @ARGV here, cause GetOptionsFromArray is not exported on perl 5.8.8


	return { command => 'help', map { $_ => undef } qw/errors error_texts warnings warning_texts options/}
		if (@ARGV && $ARGV[0] =~ /\b(help|h)\b/i);

	local $context = $self;

	my @results;
	my @getopts = map {
		($_ => sub {
			my ($name, $value) = @_;
			my $sname = "$name";# can be object instead of name.. object interpolates to string well
			push @results, { name => $sname, value => $value };
		})
	} map {
		my $type = defined($_->{type}) ? $_->{type} : 's';
		$type =  "=$type" unless $type eq '';
		map { "$_$type" } $_->{name}, @{ $_->{alias} || [] }, @{ $_->{deprecated} || [] } # TODO: it's possible to implement aliasing using GetOpt itself
	} grep { !$_->{positional} } values %{$self->{options}};

	error('getopts_error') unless GetOptions(@getopts);

	my $cfg = undef;
	my $cfg_opt = undef;

	unless ($self->{errors}) {
		if (defined(my $cmd_enc = $self->{CmdEncoding})) {
			if (my $cmd_ref = $self->{options}->{$cmd_enc}) {
				confess "CmdEncoding option should be declared as binary" unless $cmd_ref->{binary};
			}
		}

		if (defined(my $cfg_enc = $self->{ConfigEncoding})) {
			if (my $cfg_ref = $self->{options}->{$cfg_enc}) {
				confess "ConfigEncoding option should be declared as binary" unless $cfg_ref->{binary};
			}
		}

		if (defined($self->{ConfigOption}) and $cfg_opt = $self->{options}->{$self->{ConfigOption}}) {
			confess "ConfigOption option should be declared as binary" unless $cfg_opt->{binary};
			my $cfg_value = first { $_->{name} eq $self->{ConfigOption} } @results;
			$cfg_value = $cfg_value->{value} if defined $cfg_value;
			$cfg_value = $cfg_opt->{default} unless defined $cfg_value;
			if (defined $cfg_value) { # we should also check that config is 'seen'. we can only check below (so it must be seen)
				$cfg = $self->read_config($cfg_value);
				error("cannot_read_config", config => $cfg_value) unless defined $cfg;
			}
		}

		my $cmd_encoding = get_encoding($self->{CmdEncoding}, $cfg, \@results);
		my $cfg_encoding = get_encoding($self->{ConfigEncoding}, $cfg, \@results);
		$self->{cmd_encoding} = defined($cmd_encoding) ? $cmd_encoding : 'UTF-8';
		$self->{cfg_encoding} = defined($cfg_encoding) ? $cfg_encoding : 'UTF-8';
	}



	unless ($self->{errors}) {
		for (@results) { # sort needed here to define a/b order for already_specified_in_alias
			my ($optref, $is_alias) = $self->get_option_ref($_->{name});
			$optref||confess;
			warning('deprecated_option', option => $_->{name}, main => $self->{optaliasmap}->{$_->{name}})
				if $is_alias && $self->{deprecated_options}->{$_->{name}};

			error('already_specified_in_alias', ($optref->{original_option} lt $_->{name}) ?
					(a => $optref->{original_option}, b => $_->{name}) :
					(b => $optref->{original_option}, a => $_->{name})
				)
					if ((defined $optref->{value}) && !$optref->{list} && $optref->{source} eq 'option' );

			my $decoded;
			if ($optref->{binary}) {
				$decoded = $_->{value};
			} else {
				$decoded = $self->decode_option_value($_->{value});
				last unless defined $decoded;
			}

			if ($optref->{list}) {
				if (defined $optref->{value}) {
					push @{ $optref->{value} }, $decoded;
				} else {
					@{$optref}{qw/value source/} =	([ $decoded ], 'list');
				}
				push @{$self->{option_list} ||= []}, { name => $optref->{name}, value => $decoded };
			} else {
				# fill from options from command line
				@{$optref}{qw/value source original_option is_alias/} =	($decoded, 'option', $_->{name}, $is_alias);
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
		if (defined $cfg) {
			for (keys %$cfg) {
				my ($optref, $is_alias) = $self->get_option_ref($_);
				if ($optref) {
					if ($optref->{list}) {
						error('list_options_in_config', option => $_);
					} elsif (!defined $optref->{value}) {
						# fill from config
						my $decoded = $optref->{binary} ? $cfg->{$_} : $self->decode_config_value($cfg->{$_});
						last unless defined $decoded;
						@{$optref}{qw/value source/} = ($decoded, 'config'); # TODO: support for array options??
					}
				} else {
					error('unknown_config_option', option => $_);
				}
			}
		}
	}
	unless ($self->{errors}) {

		for (values %{$self->{options}}) {
			# fill from default values
			@{$_}{qw/value source/} = ($_->{default}, 'default') if (!defined($_->{value}) && defined($_->{default}));#$_->{seen} &&
		}

		$self->{preinitialize}->() if $self->{preinitialize};

		$self->{positional_tail} = \@ARGV; #[map { decode($self->{cmd_encoding}, $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC) } @ARGV];

		$self->{commands}->{$command}->{cb}->(); # the callback!

		for (qw/ConfigOption ConfigEncoding CmdEncoding/) {
			confess "Special option '$_' must be seen" if $self->{$_} && !$self->{options}{$self->{$_}}{seen};
		}

		for (values %{$self->{options}}) {
			error('unexpected_option', option => _real_option_name($_)) if defined($_->{value}) && ($_->{source} eq 'option') && !$_->{seen}; # TODO: test validation same way
		}

		unless ($self->{errors}) {
			if (@ARGV) {
				unless (defined eval {
					error('unexpected_argument', a => decode($self->{cmd_encoding}, shift @ARGV, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)); 1;
				}) {
					error("options_encoding_error", encoding => $self->{cmd_encoding}); #TODO: not utf!
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
		options => $self->{data},
		option_list => $self->{option_list},
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


sub validation(@)
{
	my ($name, $message, $cb, %opts) = (shift, shift, pop @_, @_);
	confess "undeclared option" unless defined $context->{options}->{$name};
	push @{ $context->{options}->{$name}->{validations} }, {  %opts, 'message' => $message, cb => $cb }
		unless $context->{override_validations} && exists($context->{override_validations}->{$name});
	$name;
}

sub command($@)
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
					@{$option}{qw/value source/} = (decode($context->{cmd_encoding}||'UTF-8', $v, Encode::DIE_ON_ERR|Encode::LEAVE_SRC), 'positional');
				}) {
					error("options_encoding_error", encoding => $context->{cmd_encoding}||'UTF-8'); # TODO: actually remove UTF and fix tests
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
					error ({ format => $v->{message}, a => _real_option_name $opt, value => $_}),
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
	my $name = @_ ? shift : $_;
	assert_option for $name;
	return defined($context->{options}->{$name}->{value})
};

# TODO: test
sub explicit(@) # TODO: test that it works with arrays
{
	my $name = @_ ? shift : $_;
	return present($name) && $context->{options}->{$name}->{source} eq 'option'
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

sub impose(@)
{
	my ($name, $value) = @_;
	assert_option for $name;
	my $opt = $context->{options}->{$name};
	$opt->{source} = 'impose';
	$opt->{value} = $value;
	return $name;
};


sub lists(@)
{
	my @a = @_;
	grep { my $o = $_; first { $_ eq $o->{name} } @a; } @{$context->{option_list}};
}

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
	open (my $F, "<:crlf", $filename) || return;
	my %newconfig;
	local $_;
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
