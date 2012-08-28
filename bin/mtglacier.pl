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

use strict;
use warnings;
use lib qw(lib);

use URI;
use IO::Select;
use IO::Pipe;
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
use Getopt::Long;






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






my ($P) = @_;
my ($src, $vault, $journal, $max_number_of_files, $multifile);
my $maxchildren = 10;
my $config = {};
my $config_filename;

# featurezed- different implementations of upload
$multifile = 1;


if (GetOptions("config=s" => \$config_filename,
                "from-dir:s" => \$src,
                "to-vault=s" => \$vault,
                "journal=s" => \$journal,
                "concurrency:i" => \$maxchildren,
                "max-number-of-files:i"  => \$max_number_of_files,
    ) && (scalar @ARGV == 1) ) {
    my $action = shift @ARGV;

    if ($action eq 'sync') {
        die "Please specify from-dir" unless -d $src;
        die "Not a directory" unless -d $src;
        read_config($config, $config_filename);
        my $files = read_journal($journal);
        my $filelist = [];
        find({ wanted => sub { push @$filelist, { absfilename => $_, relfilename => File::Spec->abs2rel($_, $src) } if -s $_ }, no_chdir => 1}, ($src));
        process_forks(action => "sync", filelist => $filelist, files => $files, key => $config->{key}, secret => $config->{secret}, vault => $vault, journal => $journal);
    } elsif ($action eq 'purge-vault') {
        read_config($config, $config_filename);
        my $files = read_journal($journal);
        unless (scalar keys %$files) {
            print "Nothing to delete\n";
            exit(0);
        }
        process_forks(action => "purge-vault", files => $files, key => $config->{key}, secret => $config->{secret}, vault => $vault, journal => $journal);
    } elsif ($action eq 'restore') {
        read_config($config, $config_filename);
        my $files = read_journal($journal);
        die unless $max_number_of_files;
        process_forks(action => "restore", files => $files, key => $config->{key}, secret => $config->{secret}, vault => $vault, journal => $journal, max_number_of_files => $max_number_of_files);
    } elsif ($action eq 'restore-completed') {
        read_config($config, $config_filename);
        my $files = read_journal($journal);
        process_forks(action => "restore-completed", files => $files, key => $config->{key}, secret => $config->{secret}, vault => $vault, journal => $journal, max_number_of_files => $max_number_of_files);
    } elsif ($action eq 'check-local-hash') {
        read_config($config, $config_filename);
        my $files = read_journal($journal);
        for my $f (keys %$files) {
            my $file=$files->{$f};
            my $th = TreeHash->new();
            if (-f $file->{absfilename}) {
                open my $F, "<$file->{absfilename}";
                binmode $F;
                $th->eat_file($F);
                close $F;
                $th->calc_tree();
                my $treehash = $th->get_final_hash();
                if (-s $file->{absfilename} == $file->{size}) {
                    if ($treehash eq $files->{$f}->{treehash}) {
                        print "OK $f $files->{$f}->{size} $files->{$f}->{treehash}\n";
                    } else {
                        print "TREEHASH MISSMATCH $f\n";
                    }
                } else {
                        print "SIZE MISSMATCH $f\n";
                }
            } else {
                    print "MISSED $f\n";
            }
        }
    } else {
        die "Wrong usage";
    }
} else {
    die "Wrong options";
}






sub read_journal
{
    my ($journal) = @_;
    my ($files) = ({});
    return {} unless -s $journal;
    open F, "<$journal";
    while (<F>) {
        chomp;
        if (/^\d+\s+CREATED\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*?)$/) {
            my ($archive_id, $size, $treehash, $relfilename) = ($1,$2,$3,$4);
            $files->{$relfilename} = { archive_id => $archive_id, size => $size, treehash => $treehash, absfilename => File::Spec->rel2abs($relfilename, $src) };
        } elsif (/^\d+\s+DELETED\s+(\S+)\s+(.*?)$/) {
            delete $files->{$2} if $files->{$2}; # TODO: exception or warning if $files->{$2}
        }
    }
    close F;
    return $files;
}



sub process_forks
{
    my (%args) = @_;
    # parent's data
    my $disp_select = IO::Select->new();
    my $parent_pid = $$;
    my $children = {};
    # child/parent code
    for my $n (1..$maxchildren) {
        my ($ischild, $child_fromchild, $child_tochild) = create_child($children, $disp_select);
        if ($ischild) {
            $SIG{INT} = $SIG{TERM} = sub { kill(12, $parent_pid); print STDERR "CHILD($$) SIGINT\n"; exit(1); };
            $SIG{USR2} = sub { exit(0); };
            # child code
            my $C = ChildWorker->new(region => $config->{region}, key => $config->{key}, secret => $config->{secret}, vault => $args{vault}, fromchild => $child_fromchild, tochild => $child_tochild);
            $C->process();
            kill(2, $parent_pid);
            exit(1);
        }
    }
    $SIG{INT} = $SIG{TERM} = $SIG{CHLD} = sub { $SIG{CHLD}='IGNORE';kill (12, keys %$children) ; print STDERR "PARENT Exit\n"; exit(1); };
    $SIG{USR2} = sub {  $SIG{CHLD}='IGNORE';print STDERR "PARENT SIGUSR2\n"; exit(1); };
    my $P = ParentWorker->new(children => $children, disp_select => $disp_select);


    if ($args{action} eq 'sync') {
        if (!$multifile) {
        for (@{ $args{filelist} }) {
            my ($absfilename, $relfilename) = ($_->{absfilename}, $_->{relfilename});
            next unless -f $absfilename;
            unless ($args{files}->{$relfilename}) {
                my $ft = JobProxy->new(job => FileCreateJob->new(filename => $absfilename, relfilename => $relfilename, partsize => 1048576*2));
                my $R = $P->process_task($args{journal}, $ft);
                die unless $R;
                $args{files}->{$relfilename} = {archive_id => $R->{archive_id} };
            } else {
                print "Skip $relfilename\n";
            }
        }
        } else {
            my @joblist;
            for (@{ $args{filelist} }) {
                my ($absfilename, $relfilename) = ($_->{absfilename}, $_->{relfilename});
                next unless -f $absfilename;
                unless ($args{files}->{$relfilename}) {
                    my $ft = JobProxy->new(job => FileCreateJob->new(filename => $absfilename, relfilename => $relfilename, partsize => 1048576*2));
                    push @joblist, $ft;
                } else {
                    print "Skip $relfilename\n";
                }
            }
            if (scalar @joblist) {
                my $lt = JobListProxy->new(jobs => \@joblist);
                my $R = $P->process_task($args{journal}, $lt);
                die unless $R;
                $args{files}={};
            }
        }
    } elsif ($args{action} eq 'purge-vault') {
        my @filelist = map { {archive_id => $args{files}->{$_}->{archive_id}, relfilename =>$_ } } keys %{$args{files}};
        my $ft = JobProxy->new(job => FileListDeleteJob->new(archives => \@filelist ));
        my $R = $P->process_task($args{journal}, $ft);
        $args{files} = {};
        die unless $R;
    } elsif ($args{action} eq 'restore') {
        my @filelist =  grep { ! -f $_->{filename} } map { {archive_id => $args{files}->{$_}->{archive_id}, relfilename =>$_, filename=> $args{files}->{$_}->{absfilename} } } keys %{$args{files}};
        @filelist  = splice(@filelist, 0, $args{max_number_of_files});
        die "Nothing to restore" unless scalar @filelist;
        my $ft = JobProxy->new(job => FileListRetrievalJob->new(archives => \@filelist ));
        my $R = $P->process_task($args{journal}, $ft);
        $args{files} = {};
        die unless $R;
    } elsif ($args{action} eq 'restore-completed') {
        my %filelist =  map { $_->{archive_id} => $_ } grep { ! -f $_->{filename} } map { {archive_id => $args{files}->{$_}->{archive_id}, relfilename =>$_, filename=> $args{files}->{$_}->{absfilename} } } keys %{$args{files}};
        die "Nothing to restore" unless scalar keys %filelist;
        my $ft = JobProxy->new(job => RetrievalFetchJob->new(archives => \%filelist ));
        my $R = $P->process_task($args{journal}, $ft);
        $args{files} = {};
        die unless $R;
    } else {
        die;
    }


    $SIG{INT} = $SIG{TERM} = $SIG{CHLD} = $SIG{USR2}='IGNORE';
    kill (12, keys %$children);
    while(wait() != -1) { print STDERR "wait\n";};
    print STDERR "OK DONE\n";
    exit(0);
}


#
# child/parent code
#
sub create_child
{
  my ($children, $disp_select) = @_;

  my $fromchild = new IO::Pipe;
  #log("created fromchild pipe $!", 10) if level(10);
  my $tochild = new IO::Pipe;
  #log("created tochild pipe $!", 10) if level(10);
  my $pid;
  my $parent_pid = $$;

  if($pid = fork()) { # Parent

   $fromchild->reader();
   $fromchild->autoflush(1);
   $fromchild->blocking(1);
   binmode $fromchild;

   $tochild->writer();
   $tochild->autoflush(1);
   $tochild->blocking(1);
   binmode $tochild;

   $disp_select->add($fromchild);
   $children->{$pid} = { pid => $pid, fromchild => $fromchild, tochild => $tochild };

   return (0, undef, undef);
  } elsif (defined ($pid)) { # Child

   $fromchild->writer();
   $fromchild->autoflush(1);
   $fromchild->blocking(1);
   binmode $fromchild;

   $tochild->reader();
   $tochild->autoflush(1);
   $tochild->blocking(1);
   binmode $tochild;


   undef $disp_select; # we discard tonns of unneeded pipes !
   undef $children;


   return (1, $fromchild, $tochild);
  } else {
    die "Cannot fork()";
  }
}

sub read_config
{
    my ($config, $filename) = @_;
    die "config file not found $filename" unless -f $filename;
    open F, "<$filename";
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

        $config->{$name} = $value;
    }
    close F;
    die "[key] missed in config" unless defined($config->{key});
    die "[secret] missed in config" unless defined($config->{secret});
    die "[region] missed in config" unless defined($config->{region});
    return $config;
}


__END__

