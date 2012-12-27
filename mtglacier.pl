#!/usr/bin/perl

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

package main;

use strict;
use warnings;
use utf8;
use open qw/:std :utf8/; # actually, we use "UTF-8" in other places.. UTF-8 is more strict than utf8 (w/out hypen)

our $VERSION = "0.78beta";


use URI;
use ParentWorker;
use ChildWorker;
use JobProxy;
use FileCreateJob;
use FileListDeleteJob;
use FileListRetrievalJob;
use RetrievalFetchJob;
use JobListProxy;
use File::Find ;
use File::Spec;
use Journal;
use ConfigEngine;
use ForkEngine;
use Carp;





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




print "MT-AWS-Glacier, part of MT-AWS suite, Copyright (c) 2012  Victor Efimov http://mt-aws.com/ Version $VERSION\n";

my ($P) = @_;
my ($src, $vault, $journal);
my $maxchildren = 4;
my $config = {};
my $config_filename;


my ($errors, $warnings, $action, $options) = ConfigEngine->new()->parse_options(@ARGV);


for (@$warnings) {
	warn "WARNING: $_";;
}	
if ($errors) {
	die $errors->[0];
}




if ($action eq 'sync') {
	die "Not a directory $options->{dir}" unless -d $options->{dir};
	
	my $partsize = delete $options->{partsize};
	
	my $j = Journal->new(journal_file => $options->{journal}, root_dir => $options->{dir});
	
	my $FE = ForkEngine->new(options => $options);
	$FE->start_children();
	
	$j->read_journal();
	$j->read_new_files($options->{'max-number-of-files'});
	
	my @joblist;
	for (@{ $j->{newfiles_a} }) {
		my ($absfilename, $relfilename) = ($j->absfilename($_->{relfilename}), $_->{relfilename});
		my $ft = JobProxy->new(job => FileCreateJob->new(filename => $absfilename, relfilename => $relfilename, partsize => 1048576*$partsize));
		push @joblist, $ft;
	}
	if (scalar @joblist) {
		my $lt = JobListProxy->new(jobs => \@joblist);
		my $R = $FE->{parent_worker}->process_task($lt, $j);
		die unless $R;
	}
	$FE->terminate_children();
} elsif ($action eq 'purge-vault') {
	my $j = Journal->new(journal_file => $options->{journal});
	
	my $FE = ForkEngine->new(options => $options);
	$FE->start_children();
	
	$j->read_journal();
	my $files = $j->{journal_h};
	if (scalar keys %$files) {
		my @filelist = map { {archive_id => $files->{$_}->{archive_id}, relfilename =>$_ } } keys %{$files};
		my $ft = JobProxy->new(job => FileListDeleteJob->new(archives => \@filelist ));
		my $R = $FE->{parent_worker}->process_task($ft, $j);
		die unless $R;
	} else {
		print "Nothing to delete\n";
	}
	$FE->terminate_children();
} elsif ($action eq 'restore') {
	my $j = Journal->new(journal_file => $options->{journal}, root_dir => $options->{dir});
	confess unless $options->{'max-number-of-files'};
			
	my $FE = ForkEngine->new(options => $options);
	$FE->start_children();
	
	$j->read_journal();
	my $files = $j->{journal_h};
	# TODO: refactor
	my @filelist =	grep { ! -f $_->{filename} } map { {archive_id => $files->{$_}->{archive_id}, relfilename =>$_, filename=> $j->absfilename($_) } } keys %{$files};
	@filelist  = splice(@filelist, 0, $options->{'max-number-of-files'});
	if (scalar @filelist) {
		my $ft = JobProxy->new(job => FileListRetrievalJob->new(archives => \@filelist ));
		my $R = $FE->{parent_worker}->process_task($ft, $j);
		die unless $R;
	} else {
		print "Nothing to restore\n";
	}
	$FE->terminate_children();
} elsif ($action eq 'restore-completed') {
	my $j = Journal->new(journal_file => $options->{journal}, root_dir => $options->{dir});
	
	my $FE = ForkEngine->new(options => $options);
	$FE->start_children();
	
	$j->read_journal();
	my $files = $j->{journal_h};
	# TODO: refactor
	my %filelist =	map { $_->{archive_id} => $_ } grep { ! -f $_->{filename} } map { {archive_id => $files->{$_}->{archive_id}, relfilename =>$_, filename=> $j->absfilename($_) } } keys %{$files};
	if (scalar keys %filelist) {
		my $ft = JobProxy->new(job => RetrievalFetchJob->new(archives => \%filelist ));
		my $R = $FE->{parent_worker}->process_task($ft, $j);
		die unless $R;
	} else {
		print "Nothing to restore\n";
	}
	$FE->terminate_children();
} elsif ($action eq 'check-local-hash') {
	my $j = Journal->new(journal_file => $options->{journal}, root_dir => $options->{dir});
	$j->read_journal();
	my $files = $j->{journal_h};
	
	my ($error_hash, $error_size, $error_missed, $no_error) = (0,0,0,0);
	for my $f (keys %$files) {
		my $file=$files->{$f};
		my $th = TreeHash->new();
		my $absfilename = $j->absfilename($f);
		if (-f $absfilename ) {
			open my $F, "<", $absfilename;
			binmode $F;
			$th->eat_file($F);
			close $F;
			$th->calc_tree();
			my $treehash = $th->get_final_hash();
			if (-s $absfilename == $file->{size}) {
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
	print "TOTALS:\n$no_error OK\n$error_hash TREEHASH MISSMATCH\n$error_size SIZE MISSMATCH\n$error_missed MISSED\n";
	exit(1) if $error_hash || $error_size || $error_missed;
} elsif ($action eq 'retrieve-inventory') {
	my $req = GlacierRequest->new($options);
	my $r = $req->retrieve_inventory();
	print $r->dump;
} elsif ($action eq 'download-inventory') {
	my $req = GlacierRequest->new($options);
	my $r = $req->download_inventory($options->{'job-id'}, $options->{'output-journal'});
	
	my $STR = $r->content;
	
	open F, ">_str";
	binmode F;
	print F $STR;
	close F;
	
	my $data = JSON::XS->new->allow_nonref->utf8->decode($STR);
	for (@{$data->{'ArchiveList'}}) {
		print $_->{ArchiveId};
		print "\t";
		print $_->{ArchiveDescription};
		print "\t";
		print $_->{CreationDate};
		print "\t";
		print $_->{SHA256TreeHash};
		print "\t";
		my ($f, $m) = MetaData::meta_decode($_->{ArchiveDescription});
		print "$m\t$f\n";
	}
} else {
	die "Wrong usage";
}


1;

__END__

