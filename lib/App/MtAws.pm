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

package App::MtAws;

use strict;
use warnings;
use utf8;

our $VERSION = "0.89beta";

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
use App::MtAws::ForkEngine;
use Carp;
use File::stat;
use App::MtAws::CreateVaultJob;
use App::MtAws::DeleteVaultJob;
use App::MtAws::Utils;


# TODO: can be replaced with perl pragmas
$SIG{__DIE__} = sub {
	if ($^S == 0) {
		print STDERR "DIE outside EVAL block [$^S]\n";
		for my $s (0..$#_) { dcs("Fatal Error: $^S $_[$s]"); };
		exit(1); 
	} else {
		print STDERR "DIE inside EVAL block\n";;
		for my $s (0..$#_) { dcs("Fatal Error: $^S $_[$s]"); };
	}
};

# TODO: better use Carp
sub dcs
{
  my ($p1, $p2) = @_;
  # get call stack^
  my $cs='';
  for (my $i=1; $i<20; $i++) {
    my ($package, $filename, $line, $subroutine,
        $hasargs, $wantarray, $evaltext, $is_require) = caller($i);
    last if ( ! defined($package) );
    $cs = "\n$subroutine($filename:$line)" . $cs;
  }
  $cs = "Call stack: $cs\n";
  print STDERR $cs.$p1;
}

sub main
{
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
		print STDERR "\n";
		exit 1;
	}
	if ($action ne 'help') {
		binmode STDOUT, ":encoding($options->{'terminal-encoding'})";
		binmode STDERR, ":encoding($options->{'terminal-encoding'})";
	}
	
	
	my %journal_opts = ( journal_encoding => $options->{'journal-encoding'}, filenames_encoding => $options->{'filenames-encoding'} );
	
	if ($action eq 'sync') {
		die "Not a directory $options->{dir}" unless -d binaryfilename $options->{dir};
		
		my $partsize = delete $options->{partsize};
		
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, root_dir => $options->{dir});
		
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
		$j->read_journal(should_exist => 0);
		$j->read_new_files($options->{'max-number-of-files'});
		$j->open_for_write();
		
		my @joblist;
		for (@{ $j->{newfiles_a} }) {
			my ($absfilename, $relfilename) = ($j->absfilename($_->{relfilename}), $_->{relfilename});
			my $ft = App::MtAws::JobProxy->new(job => App::MtAws::FileCreateJob->new(filename => $absfilename, relfilename => $relfilename, partsize => ONE_MB*$partsize));
			push @joblist, $ft;
		}
		if (scalar @joblist) {
			my $lt = App::MtAws::JobListProxy->new(jobs => \@joblist);
			my $R = $FE->{parent_worker}->process_task($lt, $j);
			die unless $R;
		}
		$j->close_for_write();
		$FE->terminate_children();
	} elsif ($action eq 'upload-file') {
		
		defined(my $relfilename = $options->{relfilename})||confess;
		my $partsize = delete $options->{partsize};
		
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal});
		
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
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
		
		my $R = $FE->{parent_worker}->process_task($ft, $j);
		die unless $R;
		$j->close_for_write();
		$FE->terminate_children();
	} elsif ($action eq 'purge-vault') {
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal});
		
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
		$j->read_journal(should_exist => 1);
		$j->open_for_write();
		
		my $files = $j->{journal_h};
		if (scalar keys %$files) {
			my @filelist = map { {archive_id => $files->{$_}->{archive_id}, relfilename =>$_ } } keys %{$files};
			my $ft = App::MtAws::JobProxy->new(job => App::MtAws::FileListDeleteJob->new(archives => \@filelist ));
			my $R = $FE->{parent_worker}->process_task($ft, $j);
			die unless $R;
		} else {
			print "Nothing to delete\n";
		}
		$j->close_for_write();
		$FE->terminate_children();
	} elsif ($action eq 'restore') {
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, root_dir => $options->{dir});
		confess unless $options->{'max-number-of-files'};
				
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
		$j->read_journal(should_exist => 1);
		$j->open_for_write();
		
		my $files = $j->{journal_h};
		# TODO: refactor
		my @filelist =	grep { ! -f binaryfilename $_->{filename} } map { {archive_id => $files->{$_}->{archive_id}, relfilename =>$_, filename=> $j->absfilename($_) } } keys %{$files};
		@filelist  = splice(@filelist, 0, $options->{'max-number-of-files'});
		if (scalar @filelist) {
			my $ft = App::MtAws::JobProxy->new(job => App::MtAws::FileListRetrievalJob->new(archives => \@filelist ));
			my $R = $FE->{parent_worker}->process_task($ft, $j);
			die unless $R;
		} else {
			print "Nothing to restore\n";
		}
		$j->close_for_write();
		$FE->terminate_children();
	} elsif ($action eq 'restore-completed') {
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, root_dir => $options->{dir});
		
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
		$j->read_journal(should_exist => 1);
		
		my $files = $j->{journal_h};
		# TODO: refactor
		my %filelist =	map { $_->{archive_id} => $_ } grep { ! binaryfilename -f $_->{filename} } map { {archive_id => $files->{$_}->{archive_id}, mtime => $files->{$_}{mtime}, relfilename =>$_, filename=> $j->absfilename($_) } } keys %{$files};
		if (scalar keys %filelist) {
			my $ft = App::MtAws::JobProxy->new(job => App::MtAws::RetrievalFetchJob->new(archives => \%filelist ));
			my $R = $FE->{parent_worker}->process_task($ft, $j);
			die unless $R;
		} else {
			print "Nothing to restore\n";
		}
		$FE->terminate_children();
	} elsif ($action eq 'check-local-hash') {
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{journal}, root_dir => $options->{dir});
		$j->read_journal(should_exist => 1);
		my $files = $j->{journal_h};
		
		my ($error_hash, $error_size, $error_missed, $error_mtime, $no_error) = (0,0,0,0,0);
		for my $f (keys %$files) {
			my $file=$files->{$f};
			my $th = App::MtAws::TreeHash->new();
			my $absfilename = $j->absfilename($f);
			if (-f binaryfilename $absfilename ) {
				my $F = open_file($absfilename, mode => '<', binary => 1);
				$th->eat_file($F); # TODO: don't calc tree hash if size differs!
				close $F;
				$th->calc_tree();
				my $treehash = $th->get_final_hash();
				if (defined($file->{mtime}) && (my $actual_mtime = stat(binaryfilename $absfilename)->mtime) != $file->{mtime}) {
					print "MTIME missmatch $f $file->{mtime} != $actual_mtime\n";
					++$error_mtime;
				}
				if (-s binaryfilename($absfilename) == $file->{size}) {
					if ($treehash eq $files->{$f}->{treehash}) {
						print "OK $f $files->{$f}->{size} $files->{$f}->{treehash}\n";
						++$no_error;
					} else {
						print "TREEHASH MISSMATCH $f\n";
						++$error_hash;
					}
				} else {
						print "SIZE MISSMATCH $f\n";
						++$error_size;
				}
			} else {
					print "MISSED $f\n";
					++$error_missed;
			}
		}
		print "TOTALS:\n$no_error OK\n$error_mtime MODIFICATION TIME MISSMATCHES\n$error_hash TREEHASH MISSMATCH\n$error_size SIZE MISSMATCH\n$error_missed MISSED\n";
		print "($error_mtime of them have File Modification Time altered)\n";
		exit(1) if $error_hash || $error_size || $error_missed;
	} elsif ($action eq 'retrieve-inventory') {
		$options->{concurrency} = 1; # TODO implement this in ConfigEngine
				
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
		#$j->read_journal(should_exist => 1);
		#$j->open_for_write();
		
		my $ft = App::MtAws::JobProxy->new(job => App::MtAws::RetrieveInventoryJob->new());
		my $R = $FE->{parent_worker}->process_task($ft, undef);
		#$j->close_for_write();
		$FE->terminate_children();
	} elsif ($action eq 'download-inventory') {
		$options->{concurrency} = 1; # TODO implement this in ConfigEngine
		my $j = App::MtAws::Journal->new(%journal_opts, journal_file => $options->{'new-journal'});
				
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
		
		my $ft = App::MtAws::JobProxy->new(job => App::MtAws::InventoryFetchJob->new());
		my $R = $FE->{parent_worker}->process_task($ft, undef);
		# here we can have response from both JobList or Inventory output..
		# JobList looks like 'response' => '{"JobList":[],"Marker":null}'
		# Inventory retriebal has key 'ArchiveList'
		# TODO: implement it more clear way on level of Job/Tasks object
		
		croak if -s binaryfilename $options->{'new-journal'}; # TODO: fix race condition between this and opening file
		$j->open_for_write();
	
		my $data = JSON::XS->new->allow_nonref->utf8->decode($R->{response});
		my $now = time();
		
		for my $item (@{$data->{'ArchiveList'}}) {
			
			my ($relfilename, $mtime) = App::MtAws::MetaData::meta_decode($item->{ArchiveDescription});
			$relfilename = $item->{ArchiveId} unless defined $relfilename;
			$mtime = $now unless defined $mtime;
			
			my $creation_time = App::MtAws::MetaData::_parse_iso8601($item->{CreationDate}); # TODO: move code out
			#time archive_id size mtime treehash relfilename
			$j->add_entry({
				type => 'CREATED',
				relfilename => $relfilename,
				time => $creation_time,
				archive_id => $item->{ArchiveId},
				size => $item->{Size},
				mtime => $mtime,
				treehash => $item->{SHA256TreeHash},
			});		
		}
		$j->close_for_write();
		$FE->terminate_children();
	} elsif ($action eq 'create-vault') {
		$options->{concurrency} = 1;
				
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
		my $ft = App::MtAws::JobProxy->new(job => App::MtAws::CreateVaultJob->new(name => $options->{'vault-name'}));
		my $R = $FE->{parent_worker}->process_task($ft, undef);
		$FE->terminate_children();
	} elsif ($action eq 'delete-vault') {
		$options->{concurrency} = 1;
				
		my $FE = App::MtAws::ForkEngine->new(options => $options);
		$FE->start_children();
		
		my $ft = App::MtAws::JobProxy->new(job => App::MtAws::DeleteVaultJob->new(name => $options->{'vault-name'}));
		my $R = $FE->{parent_worker}->process_task($ft, undef);
		$FE->terminate_children();
	} elsif ($action eq 'help') {
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
Commands:
	sync
	purge-vault
	restore
	restore-completed
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
