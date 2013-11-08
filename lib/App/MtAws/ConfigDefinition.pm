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

package App::MtAws::ConfigDefinition;

our $VERSION = "1.058";

use strict;
use warnings;
use utf8;
use File::Spec;
use Encode;
use Carp;
use List::Util qw/first/;
use App::MtAws::Utils;
use App::MtAws::ConfigEngine;
use App::MtAws::Filter;
use LWP::UserAgent;

sub filter_options
{
	my $filter_error = message 'filter_error', "Error in parsing filter %s a%";
	scope 'filters', do {
		my @l = optional(qw/include exclude filter/);
		if (first { present } @l) {
			my $F = App::MtAws::Filter->new();
			for (lists @l) {
				if ($_->{name} eq 'filter') {
					$F->parse_filters($_->{value});
					return error $filter_error, a => $F->{error} if defined $F->{error};
				} elsif ($_->{name} eq 'include') {
					$F->parse_include($_->{value});
				} elsif ($_->{name} eq 'exclude') {
					$F->parse_exclude($_->{value});
				} else {
					confess;
				}
			}
			@l, custom('parsed', $F);
		} else {
			@l;
		}
	}
}

sub check_base_dir
{
	if ( present('base-dir') && !present('dir') ) {
		error('base-dir can be used only with dir');
	} elsif ( present('dir') ) {
		optional('base-dir');
	} else {
		return;
	}
}

#sub abs_dir()
#{
#	custom 'abs-dir', File::Spec->rel2abs(value('dir'));
#}

sub mandatory_maxsize
{
	unless (present(optional('check-max-file-size'))) {
		error('mandatory_with', a => 'check-max-file-size', b => seen('stdin'));
	}
	'check-max-file-size'
}

sub check_dir_or_relname
{

	message 'mutual', "%option a% and %option b% are mutual exclusive";
	message 'mandatory_with', "Need to use %option b% together with %option a%";
	if (present('filename')) {
		custom('data-type', 'filename'), mandatory('filename'), do {
			if (present('set-rel-filename')) {
				if (present('dir')) {
					error('mutual', a => seen('set-rel-filename'), b => seen('dir'));
				} else {
					custom('name-type', 'rel-filename'), mandatory('set-rel-filename'), custom('relfilename', value('set-rel-filename'));
				}
			} elsif (present('dir')) {
				custom('relfilename', do {
					validate 'dir', 'filename';
					if (valid('dir') && valid('filename')) {
						my $relfilename = File::Spec->abs2rel(value('filename'), value('dir'));
						if ($relfilename =~ m!^\.\./!) {
							error(message('filename_inside_dir',
								'File specified with "option a" should be inside directory specified in %option b%'),
								a => 'filename', b => 'dir'),
							undef;
						} else {
							$relfilename
						}
					} else {
						undef;
					}
				}), custom('name-type', 'dir'), mandatory('dir');
			} else {
				error(message('either', 'Please specify %option a% or %option b%'), a => 'set-rel-filename', b => 'dir');
			}
		}
	} elsif (present('stdin')) {
		if (present('set-rel-filename')) {
			if (present('dir')) {
				seen('stdin'), mandatory_maxsize, error('mutual', a => seen('set-rel-filename'), b => seen('dir'));
			} else {
				custom('name-type', 'rel-filename'), custom('data-type', 'stdin'), mandatory('set-rel-filename'), mandatory('stdin'),
				custom('relfilename', value('set-rel-filename')), mandatory_maxsize;
			}
		} else {
			error('mandatory_with', a => 'set-rel-filename', b => seen('stdin'))
		}
	} else {
		error(message 'Please specify filename or stdin')
	}
}

sub http_download_options
{
	scope('file_downloads', optional('segment-size'))
}

sub download_options
{
	mandatory('dir'), check_base_dir, http_download_options();
}

sub check_wait
{
	if (present('wait')) {
		mandatory('wait'), download_options
	} else {
		return;
	}
}

sub existing_journal
{
	my ($journal) = @_;
	if (defined($journal) && present($journal) && !exists $App::MtAws::ConfigEngine::context->{override_validations}->{journal}) { # TODO: this is hack!
		error('Journal file not found') unless -f binaryfilename value($journal);
	}
	$journal;
}

sub writable_journal
{
	my ($journal) = @_;
	if (defined($journal) && present($journal)) {
		my $value = binaryfilename value($journal);
		error('Journal file not writable') if (-e $value && (! -w $value or -d $value));
	}
	$journal;
}

sub empty_journal
{
	my ($journal) = @_;
	if (defined($journal) && present($journal)) {
		error('Journal file not empty - please provide empty file no write new journal') unless ! -s binaryfilename value($journal);
	}
	$journal;
}

sub check_https
{
	if (present('protocol') and value('protocol') eq 'https') {
		if (LWP::UserAgent->is_protocol_supported("https")) {
			# to get LWP version, use LWP->VERSION instead of LWP::UserAgent->VERSION
			error('LWP::UserAgent 6.x required to use HTTPS') unless LWP->VERSION() >= 6;
			require LWP::Protocol::https;
			error('LWP::Protocol::https 6.x required to use HTTPS') unless LWP::Protocol::https->VERSION && LWP::Protocol::https->VERSION >= 6;
		} else {
			error('IO::Socket::SSL or LWP::Protocol::https is not installed');
		}
	}
	return;
}

sub check_max_size
{
	if (present('check-max-file-size')) {
		if (value('check-max-file-size')/value('partsize') > 10_000) {
			seen('check-max-file-size'), error(message('partsize_vs_maxsize',
				"With current partsize %d partsizevalue%MiB and maximum allowed file size %d maxsizevalue%MiB, upload might exceed 10 000 parts.".
				"Increase %option partsize% or decrease %option maxsize%"),
				partsize => 'partsize', maxsize => 'check-max-file-size', partsizevalue => value('partsize'), maxsizevalue => value('check-max-file-size'));
		} else {
			seen('check-max-file-size')
		}
	} else {
		return;
	}
}

sub detect_opts
{

	seen('detect'), do { # TODO: movify configengine to somehow simplify this
		explicit('detect') && (!present('replace-modified')) ?
		error("option_for_command_can_be_used_only_with", a => 'detect', b => 'replace-modified', c => 'sync') :
		();
	};
}

sub sync_opts
{
	my @sync_opts = qw/new replace-modified delete-removed/;
	optional(@sync_opts);
	if (present('new') || present('replace-modified') || present('delete-removed')) {
		@sync_opts
	} else {
		impose('new', 1); # TODO: can cause problems in the future
	}
}

sub get_config
{
	my (%args) = @_;

	my $c  = App::MtAws::ConfigEngine->new(ConfigOption => 'config', CmdEncoding => 'terminal-encoding', ConfigEncoding => 'config-encoding', %args);

	$c->{preinitialize} = sub {
		set_filename_encoding $c->{options}{'filenames-encoding'}{value};
	};

	$c->define(sub {

		message 'no_command', 'Please specify command', allow_redefine=>1;
		message 'already_specified_in_alias', '%option b% specified, while %option a% already defined', allow_redefine => 1;
		message 'unexpected_argument', "Extra argument in command line: %a%", allow_redefine => 1;
		message 'mandatory', "Please specify %option a%", allow_redefine => 1;
		message 'cannot_read_config', 'Cannot read config file "%config%"';
		message 'deprecated_option', '%option% deprecated, use %main% instead';
		message 'option_for_command_can_be_used_only_with', "Option %option a% for %command c% command can be used only together with %option b%";


		for (option 'dir', deprecated => ['to-dir', 'from-dir']) {
			validation $_, message('%option a% should be less than 512 characters'), stop => 1, sub { length($_) < 512 }; # TODO: check that dir is dir
			validation $_, message('%option a% not a directory'), stop => 1, sub { -d binaryfilename };
		}

		option 'base-dir';
		validation option('leaf-optimization', default => 1), message('%option a% should be either "1" or "0"'), sub { /^[01]$/ };
		option 'follow', type=>'';

		for (option 'filename') {
			validation $_, message('%option a% not a file'), stop => 1, sub { -f binaryfilename };
			validation $_, message('%option a% file not readable'), stop => 1, sub { -r binaryfilename };
			validation $_, message('%option a% file size is zero'), stop => 1, sub { -s binaryfilename };
		}


		for (option 'set-rel-filename') {
			validation $_, message('require_relative_filename', '%option a% should be canonical relative filename'),
				stop => 1,
				sub { is_relative_filename($_) };
		}
		option 'stdin', type=>'';

		option 'vault', deprecated => 'to-vault';
		option 'config', binary => 1;
		options 'journal', 'job-id', 'max-number-of-files', 'new-journal';

		my @encodings =
			map { option($_, binary =>1, default => 'UTF-8') }
			qw/terminal-encoding config-encoding filenames-encoding journal-encoding/;

		for (@encodings) {
			validation $_, 'unknown_encoding', sub { find_encoding($_) };
		}


		my @filters = map { option($_, type => 's', list => 1) } qw/include exclude filter/;

		option 'dry-run', type=>'';

		my $invalid_format = message('invalid_format', 'Invalid format of "%a%"');
		my $must_be_an_integer = message('must_be_an_integer', '%option a% must be positive integer number');



		option('new', type=>'');
		option('replace-modified', type=>'');
		option('delete-removed', type=>'');


		# treehash, mtime, mtime-and-treehash, mtime-or-treehash
		# mtime-and-treehash := treat_as_modified if differs(mtime) && differs(treehash)
		# mtime-or-treehash := treat_as_modified if differs(mtime) or differs(treehash)
		validation
			option('detect', default => 'mtime-and-treehash'),
			$invalid_format,
			sub { my $v = $_; first { $_ eq $v } qw/treehash mtime mtime-and-treehash mtime-or-treehash always-positive size-only/ };

		my @config_opts = (
			validation(option('key'), $invalid_format, sub { /^[A-Za-z0-9]{20}$/ }),
			validation(option('secret'), $invalid_format, sub { /^[\x21-\x7e]{40}$/ }),
			validation(option('region'), $invalid_format, sub { /^[A-Za-z0-9\-]{3,20}$/ }),
			optional(validation(option('token'), $invalid_format, sub { /^[\x21-\x7e]{20,1024}$/ })),
			validation(option('timeout', default => 180), $invalid_format, sub { /^[0-9]{1,5}$/ }),
			validation(option('protocol', default => 'http'), message('protocol must be "https" or "http"'), sub { /^https?$/ }),
		);

		for (option('concurrency', type => 'i', default => 4)) {
			validation $_, $must_be_an_integer, stop => 1, sub { $_ =~ /^\d+$/ };
			validation $_, message('Max concurrency is 30,  Min is 1'), sub { $_ >= 1 && $_ <= 30 };
		}

		for (option('check-max-file-size', type => 'i')) {
			validation $_, $must_be_an_integer, stop => 1, sub { $_ =~ /^\d+$/ };
			validation $_, message('check-max-file-size should be greater than 0'), stop => 1, sub { $_ > 0 }; # TODO: %option .. %
			validation $_, message('check-max-file-size should be less than or equal to 40 000 000'), stop => 1, sub { $_ <= 40_000_000 };
		}

		for (option('partsize', type => 'i', default => 16)) {
			validation $_, $must_be_an_integer, stop => 1, sub { $_ =~ /^\d+$/ };
			validation $_, message('Part size must be power of two'), sub { ($_ != 0) && (($_ & ($_ - 1)) == 0) };
		}
		for (option('segment-size', type => 'i')) {
			validation $_, $must_be_an_integer, stop => 1, sub { $_ =~ /^\d+$/ };
			validation $_, message('%option a% must be zero or power of two'), sub { (($_ & ($_ - 1)) == 0) }; # TODO: proper format
		}

		validation positional('vault-name'), message('Vault name should be 255 characters or less and consisting of a-z, A-Z, 0-9, ".", "-", and "_"'), sub {
			/^[A-Za-z0-9\.\-_]{1,255}$/
		};

		command 'create-vault' => sub { validate(optional('config'), mandatory(@encodings), mandatory('vault-name'), mandatory(@config_opts), check_https)};
		command 'delete-vault' => sub { validate(optional('config'), mandatory(@encodings), mandatory('vault-name'), mandatory(@config_opts), check_https)};

		command 'sync' => sub {
			validate(mandatory(
				optional('config'), mandatory(@encodings), @config_opts, sync_opts, detect_opts, check_https,
				qw/dir vault concurrency partsize/, writable_journal('journal'),
				optional(qw/max-number-of-files leaf-optimization follow/),
				filter_options, optional('dry-run')
			))
		};

		command 'upload-file' => sub {
			validate(mandatory(  optional('config'), mandatory(@encodings), @config_opts, check_https, qw/vault concurrency/, writable_journal('journal'),
				check_dir_or_relname, check_base_dir, mandatory('partsize'), check_max_size  ))
		};


		command 'purge-vault' => sub {
			validate(mandatory(
				optional('config'), mandatory(@encodings), @config_opts, check_https, qw/vault concurrency/,
				writable_journal(existing_journal('journal')),
				deprecated('dir'), filter_options, optional('dry-run')
			))
		};

		command 'restore' => sub {
			validate(mandatory(
				optional('config'), mandatory(@encodings), @config_opts, check_https, qw/dir vault max-number-of-files concurrency/,
				writable_journal(existing_journal('journal')),
				filter_options, optional('dry-run')
			))
		};

		command 'restore-completed' => sub {
			validate(mandatory(
				optional('config'), mandatory(@encodings), @config_opts, check_https, qw/dir vault concurrency/, existing_journal('journal'),
				filter_options, optional('dry-run'), http_download_options
			))
		};

		command 'check-local-hash' => sub {
			validate(mandatory(
				optional('config'), mandatory(@encodings), @config_opts, check_https, qw/dir/, existing_journal('journal'), deprecated('vault'),
				filter_options, optional('dry-run')
			))
		};

		command 'retrieve-inventory' => sub {
			validate(mandatory(optional('config'), mandatory(@encodings), @config_opts, check_https, qw/vault/))
		};

		command 'download-inventory' => sub {
			validate(mandatory(optional('config'), mandatory(@encodings), @config_opts, check_https, 'vault', empty_journal('new-journal')))
		};
	});
	return $c;
}

1;
__END__
