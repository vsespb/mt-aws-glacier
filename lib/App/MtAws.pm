#!/usr/bin/env perl

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


=head1 NAME

mt-aws-glacier - Perl Multithreaded Multipart sync to Amazon Glacier 

=head1 SYNOPSIS

More info in README.md or L<https://github.com/vsespb/mt-aws-glacier> or L<http://mt-aws.com/>

=cut


package App::MtAws;

use strict;
use warnings;
use utf8;
use 5.008008; # minumum perl version is 5.8.8

our $VERSION = "0.962_3beta";

use constant ONE_MB => 1024*1024;

use App::MtAws::ParentWorker;
use App::MtAws::ChildWorker;
use App::MtAws::JobProxy;
use App::MtAws::FileCreateJob;
use App::MtAws::FileListDeleteJob;
use App::MtAws::FileListRetrievalJob;
use App::MtAws::RetrievalFetchJob;
use App::MtAws::JobListProxy;
use App::MtAws::RetrieveInventoryJob;
use App::MtAws::InventoryFetchJob;
use File::Find ;
use File::Spec;
use App::MtAws::Journal;
use App::MtAws::ConfigDefinition;
use App::MtAws::ForkEngine qw/with_forks fork_engine/;
use Carp;
use File::stat;
use IO::Handle;
use App::MtAws::CreateVaultJob;
use App::MtAws::DeleteVaultJob;
use App::MtAws::Utils;
use App::MtAws::Exceptions;
use PerlIO::encoding;


sub main
{
	unless (defined eval {process(); 1;}) {
		dump_error(q{});
		exit(1);
	}
	print "OK DONE\n";
	exit(0);
}

sub process
{
	$|=1;
	STDERR->autoflush(1); 
	print "MT-AWS-Glacier, Copyright 2012-2013 Victor Efimov http://mt-aws.com/ Version $VERSION\n\n";
	
	my ($P) = @_;
	my ($src, $vault, $journal);
	my $maxchildren = 4;
	my $config = {};
	my $config_filename;
	
	
	my $res = App::MtAws::ConfigDefinition::get_config()->parse_options(@ARGV);
	my ($action, $options) = ($res->{command}, $res->{options});
	if ($res->{warnings}) {
		while (@{$res->{warnings}}) {
			my ($warning, $warning_text) = (shift @{$res->{warnings}}, shift @{$res->{warning_texts}});
			print STDERR "WARNING: $warning_text\n" unless $warning->{format} =~ /^(deprecated_option|deprecated_command|option_deprecated_for_command)$/; # TODO: temporary disable warning
		}
	}
	if ($res->{error_texts}) {
		for (@{$res->{error_texts}}) {
			print STDERR "ERROR: ".$_."\n";
		}
		die exception cmd_error => 'Error in command line/config'
	}
	if ($action ne 'help') {
		$PerlIO::encoding::fallback = Encode::FB_QUIET;
		binmode STDERR, ":encoding($options->{'terminal-encoding'})";
		binmode STDOUT, ":encoding($options->{'terminal-encoding'})";
	}
	
	my %journal_opts = ( journal_encoding => $options->{'journal-encoding'}, filenames_encoding => $options->{'filenames-encoding'} );
	
	if ($action eq 'sync') {
		die "Not a directory $options->{dir}" unless -d binaryfilename $options->{dir};
		
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, root_dir => $options->{dir},
			filter => $options->{filters}{parsed}, leaf_optimization => $options->{'leaf-optimization'});

		require App::MtAws::SyncCommand;
		App::MtAws::SyncCommand::run($options, $j);

	} elsif ($action eq 'upload-file') {
		
		defined(my $relfilename = $options->{relfilename})||confess;
		my $partsize = delete $options->{partsize};
		
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal});
		
		with_forks 1, $options, sub {
			
			$j->read_journal(should_exist => 0);
			
			die <<"END"
File with same name alredy exists in Journal.
In the current version of mtglacier you are disallowed to store multiple versions of same file.
Multiversion will be implemented in the future versions.
END
				if (defined $j->{journal_h}->{$relfilename});
			
			if ($options->{'data-type'} ne 'filename') {
				binmode STDIN;
				check_stdin_not_empty(); # after we fork, but before we touch Journal for write and create Amazon Glacier upload id
			}
			
			$j->open_for_write();
			
			my $ft = ($options->{'data-type'} eq 'filename') ?
				App::MtAws::JobProxy->new(job => App::MtAws::FileCreateJob->new(
					filename => $options->{filename},
					relfilename => $relfilename,
					partsize => ONE_MB*$partsize)) :
				App::MtAws::JobProxy->new(job => App::MtAws::FileCreateJob->new(
					stdin => 1,
					relfilename => $relfilename,
					partsize => ONE_MB*$partsize));
			
			my ($R) = fork_engine->{parent_worker}->process_task($ft, $j);
			die unless $R;
			$j->close_for_write();
		}
	} elsif ($action eq 'purge-vault') {
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, filter => $options->{filters}{parsed});
		
		with_forks !$options->{'dry-run'}, $options, sub {
			$j->read_journal(should_exist => 1);
			
			my $archives = $j->{archive_h};
			if (scalar keys %$archives) {
				if ($options->{'dry-run'}) {
						for (keys %$archives) {
							print "Will DELETE archive $_ (filename $archives->{$_}{relfilename})\n"
						}
				} else {
					$j->open_for_write();
					my @filelist = map { {archive_id => $_, relfilename =>$archives->{$_}->{relfilename} } } keys %{$archives};
					my $ft = App::MtAws::JobProxy->new(job => App::MtAws::FileListDeleteJob->new(archives => \@filelist ));
					my ($R) = fork_engine->{parent_worker}->process_task($ft, $j);
					die unless $R;
					$j->close_for_write();
				}
			} else {
				print "Nothing to delete\n";
			}
		}
	} elsif ($action eq 'restore') {
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, root_dir => $options->{dir}, filter => $options->{filters}{parsed}, use_active_retrievals => 1);
		confess unless $options->{'max-number-of-files'};
				
		require App::MtAws::RetrieveCommand;
		App::MtAws::RetrieveCommand::run($options, $j);
	} elsif ($action eq 'restore-completed') {
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, root_dir => $options->{dir}, filter => $options->{filters}{parsed});
		
		with_forks !$options->{'dry-run'}, $options, sub {
			$j->read_journal(should_exist => 1);
			
			my $files = $j->{journal_h};
			# TODO: refactor
			my %filelist =	map { $_->{archive_id} => $_ }
				grep { ! binaryfilename -f $_->{filename} }
				map {
					my $entry = $j->latest($_);
					{
						archive_id => $entry->{archive_id}, mtime => $entry->{mtime}, size => $entry->{size},
						treehash => $entry->{treehash}, relfilename =>$_, filename=> $j->absfilename($_)
					}
				}
				keys %{$files};
			if (keys %filelist) {
				if ($options->{'dry-run'}) {
					for (keys %filelist) {
						print "Will DOWNLOAD (if available) archive $_->{archive_id} (filename $_->{relfilename})\n" for ($j->latest($_));
					}
				} else {
					my $ft = App::MtAws::JobProxy->new(job => App::MtAws::RetrievalFetchJob->new(file_downloads => $options->{file_downloads}, archives => \%filelist ));
					my ($R) = fork_engine->{parent_worker}->process_task($ft, $j);
					die unless $R;
				}
			} else {
				print "Nothing to restore\n";
			}
		}
	} elsif ($action eq 'check-local-hash') {
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, root_dir => $options->{dir}, filter => $options->{filters}{parsed});
		require App::MtAws::CheckLocalHashCommand;
		App::MtAws::CheckLocalHashCommand::run($options, $j);
	} elsif ($action eq 'retrieve-inventory') {
		$options->{concurrency} = 1; # TODO implement this in ConfigEngine
				
		with_forks 1, $options, sub {
			my $ft = App::MtAws::JobProxy->new(job => App::MtAws::RetrieveInventoryJob->new());
			my ($R) = fork_engine->{parent_worker}->process_task($ft, undef);
		}
	} elsif ($action eq 'download-inventory') {
		$options->{concurrency} = 1; # TODO implement this in ConfigEngine
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{'new-journal'});
		require App::MtAws::DownloadInventoryCommand;
		App::MtAws::DownloadInventoryCommand::run($options, $j);
	} elsif ($action eq 'create-vault') {
		$options->{concurrency} = 1;
				
		with_forks 1, $options, sub {
			my $ft = App::MtAws::JobProxy->new(job => App::MtAws::CreateVaultJob->new(name => $options->{'vault-name'}));
			my ($R) = fork_engine->{parent_worker}->process_task($ft, undef);
		}
	} elsif ($action eq 'delete-vault') {
		$options->{concurrency} = 1;
				
		with_forks 1, $options, sub {
			my $ft = App::MtAws::JobProxy->new(job => App::MtAws::DeleteVaultJob->new(name => $options->{'vault-name'}));
			my ($R) = fork_engine->{parent_worker}->process_task($ft, undef);
		}
	} elsif ($action eq 'help') {
		
		# we load here all dynamically loaded modules, to check that installation is correct.
		require App::MtAws::CheckLocalHashCommand;
		require App::MtAws::DownloadInventoryCommand;
		require App::MtAws::RetrieveCommand;
		
		print <<"END";
Usage: mtglacier.pl COMMAND [POSITIONAL ARGUMENTS] [OPTION]...

Common options:
	--config - config file
	--journal - journal file (append only)
	--dir - source local directory
	--vault - Glacier vault name
	--concurrency - number of parallel workers to run
	--max-number-of-files - max number of files to sync/restore
	--protocol - Use http or https to connect to Glacier
	--partsize - Glacier multipart upload part size
	--filter --include --exclude - File filtering
	--dry-run - Don't do anything
	--token - to be used with STS/IAM
	--timeout - socket timeout
Commands:
	sync
		--leaf-optimization - Don't use directory hardlinks count when traverse.
	purge-vault
	restore
	restore-completed
		--segment-size - Size for multi-segment download, in megabytes
	check-local-hash
	retrieve-inventory
	download-inventory
		--new-journal - Write inventory as new journal
	create-vault VAULT-NAME
	delete-vault VAULT-NAME
	upload-file
		--filename - File to upload
		--set-rel-filename - Relative filename to use in Journal (if dir not specified)
		--stdin - Upload from STDIN
		--check-max-file-size - Specify to ensure there will be less than 10 000 parts
Config format (text file):
	key=YOURKEY
	secret=YOURSECRET
	# region: eu-west-1, us-east-1 etc
	region=us-east-1
	# protocol=http (default) or https
	protocol=http

END
	
	} else {
		die "Wrong usage";
	}
}

sub check_stdin_not_empty
{
	die "Empty input from STDIN - cannot upload empty archive"
		if eof(STDIN); # we block until first byte arrive, then we put it back in to buffer
}

1;
