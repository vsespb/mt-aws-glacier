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

use strict;
use warnings;
use utf8;

use App::MtAws::ConfigEngineNew;

sub filter_options
{
	optional(qw/include exclude/);
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

sub check_dir_or_relname
{
	
	message 'mutual', "%option a% and %option b% are mutual exclusive";
	if (present('filename')) {
		custom('data-type', 'filename'), mandatory('filename'), do {
			if (present('set-rel-filename')) {
				if (present('dir')) {
					error('mutual', a => 'set-rel-filename', b => 'dir');
				} else {
					custom('name-type', 'rel-filename'), mandatory('set-rel-filename');
				}
			} elsif (present('dir')) {
				custom('name-type', 'dir'), mandatory('dir');
			} else {
				error('please specify set-rel-filename or dir')
			}
		}
	} elsif (present('stdin')) {
		if (present('set-rel-filename')) {
			if (present('dir')) {
				error('mutual', a => 'set-rel-filename', b => 'dir');
			} else {
				custom('name-type', 'rel-filename'), custom('data-type', 'stdin'), mandatory('set-rel-filename'), mandatory('stdin')
			}
		} else {
			error('need use set-rel-filename together with stdin')
		}
	} else {
		error('please specify filename or stdin')
	}
}

sub download_options
{
	mandatory('dir'), check_base_dir, optional('chunksize');
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
	if (defined($journal) && present($journal) && !exists $App::MtAws::ConfigEngineNew::context->{override_validations}->{journal}) { # TODO: this is hack!
		error('Journal file not found') unless -r value($journal);
	}
	$journal;
}

sub writable_journal
{
	my ($journal) = @_;
	if (defined($journal) && present($journal)) {
		my $value = value($journal);
		error('Journal file not writable') unless (-f $value && -w $value && ! -d $value) || (! -d $value);
	}
	$journal;
}

sub empty_journal
{
	my ($journal) = @_;
	if (defined($journal) && present($journal)) {
		error('Journal file not empty - please provide empty file no write new journal') unless ! -s value($journal);
	}
	$journal;
}

sub check_https
{
	if (present('protocol') and value('protocol') eq 'https') {
		error('IO::Socket::SSL or LWP::Protocol::https is not installed') unless LWP::UserAgent->is_protocol_supported("https");
		error('LWP::UserAgent 6.x required to use HTTPS') unless LWP->VERSION() >= 6;
		require LWP::Protocol::https;
		error('LWP::Protocol::https 6.x required to use HTTPS') unless LWP::Protocol::https->VERSION && LWP::Protocol::https->VERSION >= 6;
	}
}

sub deprecate_from_dir
{
	if (present('dir')) {
		warning('options from-dir/dir deprecated for this command');
		undef raw_option('dir')->{value};
	}
	return;
}

sub deprecate_to_vault
{
	if (present('vault')) {
		warning('vault is not needed for this command');
		undef raw_option('vault')->{value};
	}
	return;
}

sub get_config
{
	my (%args) = @_;
	
	my $c  = App::MtAws::ConfigEngineNew->new(%args);
	
	$c->define(sub {
		
		message 'no_command', 'Please specify command', allow_redefine=>1;
		message 'already_specified_in_alias', '%option b% specified, while %option a% already defined', allow_redefine => 1;
		message 'unexpected_argument', "Extra argument in command line: %a%", allow_redefine => 1;
		message 'mandatory', "Please specify %option a%", allow_redefine => 1;
		message 'cannot_read_config', 'Cannot read config file "%config%"';
		message 'deprecated_option', '%option% deprecated, use %main% instead';
		
		
		option 'dir', deprecated => ['to-dir', 'from-dir'];
		option 'vault', deprecated => 'to-vault';
		options 'config', 'journal', 'job-id', 'max-number-of-files', 'new-journal';
		
		my $invalid_format = message('invalid_format', 'Invalid format of "%a%"');
		my $must_be_an_integer = message('must_be_an_integer', '%option a% must be an integer number');

		my @config_opts = (
			validation(option('key'), $invalid_format, sub { /^[A-Za-z0-9]{20}$/ }),
			validation(option('secret'), $invalid_format, sub { /^[\x21-\x7e]{40}$/ }),
			validation(option('region'), $invalid_format, sub { /^[A-Za-z0-9\-]{3,20}$/ }),
			validation(option('protocol', default => 'http'), message('protocol must be "https" or "http"'), sub { /^https?$/ }),
		);
		
		for (option('concurrency', default => 4)) {
			validation $_, $must_be_an_integer, sub { $_ =~ /^\d+$/ }; # TODO: type=i
			validation $_, message('Max concurrency is 30,  Min is 1'), sub { $_ >= 1 && $_ <= 30 };
		}
		
		for (option('partsize', default => 16)) {
			validation $_, $must_be_an_integer, sub { $_ =~ /^\d+$/ }; # TODO: type=i
			validation $_, message('Part size must be power of two'), sub { ($_ != 0) && (($_ & ($_ - 1)) == 0) };
		}
		
		
		validation positional('vault-name'), message('Vault name should be 255 characters or less and consisting of a-z, A-Z, 0-9, ".", "-", and "_"'), sub {
			/^[A-Za-z0-9\.\-_]{1,255}$/
		};
		
		command 'create-vault' => sub { validate(optional('config'), mandatory('vault-name'), mandatory(@config_opts)),	};
		command 'delete-vault' => sub { validate(optional('config'), mandatory('vault-name'), mandatory(@config_opts)),	};
		
		command 'sync' => sub {
			validate(mandatory(optional('config'), @config_opts, qw/dir vault concurrency partsize/, writable_journal('journal')), optional(qw/max-number-of-files/) )
		};
		
		command 'purge-vault' => sub {
			# TODO: deprecated option from-dir
			validate(mandatory(  optional('config'), @config_opts, qw/vault concurrency/, writable_journal(existing_journal('journal')), deprecate_from_dir(optional('dir'))  ))
		};
		
		command 'restore' => sub {
			validate(mandatory(optional('config'), @config_opts, qw/dir vault max-number-of-files concurrency/, writable_journal(existing_journal('journal'))))
		};
		
		command 'restore-completed' => sub {
			validate(mandatory(optional('config'), @config_opts, qw/dir vault concurrency/, existing_journal('journal')))
		};
		
		command 'check-local-hash' => sub {
			# TODO: deprecated option to-vault
			validate(mandatory(  optional('config'), @config_opts, qw/dir/, existing_journal('journal'), deprecate_to_vault(optional('vault')) ))
		};
		
		command 'retrieve-inventory' => sub {
			validate(mandatory(optional('config'), @config_opts, qw/vault/))
		};
		
		command 'download-inventory' => sub {
			validate(mandatory(optional('config'), @config_opts, 'vault', empty_journal('new-journal')))
		};
	});
	return $c;
}

1;
__END__

		my @remote = options qw/concurrency key vault secret region protocol/;
		my @dir_or_relname = options qw/set-rel-filename dir/;
		options qw/base-dir include exclude partsize journal filename stdin wait chunksize zz/;
		
		message 'mandatory', "Please specify %option a%";
		#positional 'vault-name';
		#validation 'vault-name', sub { /\w+/ };
	
		validation 'concurrency', message('concurrency_too_high', "%option option% should be less than 30"), sub { $_ < 30 };
		
		
		command 'create-vault' => sub {
			mandatory('vault-name')
		};
		
		command 'sync' => sub {
			 mandatory( mandatory(@remote), 'journal',  mandatory('dir'), check_base_dir, optional('partsize'), filter_options ); 
		};
		command 'upload-file' => sub {
			validate mandatory(@remote), mandatory('journal'),  scope('dir', check_dir_or_relname, check_base_dir), optional('partsize'); 
		};
		command 'retrieve-file' => sub {
			validate mandatory(@remote), mandatory('journal'),  check_wait, scope('dir', check_dir_or_relname, check_base_dir), optional 'partsize' 
		};

		command 'retrieve' => sub {
			mandatory(@remote), mandatory 'journal',  check_wait, filter_options
		};
		
		command 'download' => sub {
			mandatory(@remote), mandatory 'journal',  download_options, filter_options 
		};
		
		command 'upload-file' => sub {
			mandatory(@remote), mandatory 'journal',  check_dir_or_relname, check_base_dir, optional 'partsize' 
		};
		
		command 'retrieve-file' => sub {
			mandatory(@remote), mandatory 'journal',  check_wait, check_dir_or_relname, check_base_dir, optional 'partsize' 
		};
