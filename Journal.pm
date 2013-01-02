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

package Journal;

use strict;
use warnings;
use utf8;


use File::Find ;
use File::Spec;
use Encode;
use Carp;

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->{journal_file} || die;
	$self->{journal_h} = {};
	
	$self->{used_versions} = {};
	$self->{output_version} = 'A' unless defined($self->{output_version});
	
	return $self;
}

#
# Reading journal
#

# sub read_journal

sub read_journal
{
	my ($self) = @_;
	return unless -s $self->{journal_file};
	open (F, "<:encoding(UTF-8)", $self->{journal_file});
	while (<F>) {
		chomp;
		$self->process_line($_);
	}
	close F;
	return;
}

sub process_line
{
	my ($self, $line) = @_;
		# Journal version 'A'
	
	if ($line =~ /^A\t(\d+)\tCREATED\t(\S+)\t(\d+)\t(\d+)\t(\S+)\t(.*?)$/) {
		my ($time, $archive_id, $size, $mtime, $treehash, $relfilename) = ($1,$2,$3,$4,$5,$6);
		confess "invalid filename" unless defined($relfilename = sanity_relative_filename($relfilename));
		$self->_add_file($relfilename, {
			time => $time,
			archive_id => $archive_id,
			size => $size,
			mtime => $mtime,
			treehash => $treehash,
		});
		$self->{used_versions}->{A} = 1;
	} elsif ($line =~ /^A\t(\d+)\tDELETED\t(\S+)\t(.*?)$/) {
		$self->_delete_file($3);
		$self->{used_versions}->{A} = 1;
		
	# Journal version '0'
	
	} elsif ($line =~ /^(\d+)\s+CREATED\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*?)$/) {
		my ($time, $archive_id, $size, $treehash, $relfilename) = ($1,$2,$3,$4,$5);
		confess "invalid filename" unless defined($relfilename = sanity_relative_filename($relfilename));
		#die if $self->{journal_h}->{$relfilename};
		$self->_add_file($relfilename, {
			time => $time,
			archive_id => $archive_id,
			size => $size,
			treehash => $treehash,
		});
		$self->{used_versions}->{0} = 1;
	} elsif ($line =~ /^\d+\s+DELETED\s+(\S+)\s+(.*?)$/) {
		$self->_delete_file($2);
		$self->{used_versions}->{0} = 1;
	} else {
		#die;
	}
}

sub _add_file
{
	my ($self, $relfilename, $args) = @_;
	$self->{journal_h}->{$relfilename} = $args;
}

sub _delete_file
{
	my ($self, $relfilename) = @_;
	delete $self->{journal_h}->{$relfilename} if $self->{journal_h}->{$relfilename}; # TODO: exception or warning if $files->{$2}
}

#
# Wrting journal
#

sub add_entry
{
	my ($self, $e) = @_;
	
	confess unless $self->{output_version} eq 'A';
	
	# TODO: time should be ascending?

	if ($e->{type} eq 'CREATED') {
		#" CREATED $archive_id $data->{filesize} $data->{final_hash} $data->{relfilename}"
		defined( $e->{$_} ) || confess "bad $_" for (qw/time archive_id size mtime treehash relfilename/);
		confess "invalid filename" unless defined(my $filename = sanity_relative_filename($e->{relfilename}));
		$self->_write_line("A\t$e->{time}\tCREATED\t$e->{archive_id}\t$e->{size}\t$e->{mtime}\t$e->{treehash}\t$filename");
	} elsif ($e->{type} eq 'DELETED') {
		#  DELETED $data->{archive_id} $data->{relfilename}
		defined( $e->{$_} ) || confess "bad $_" for (qw/archive_id relfilename/);
		confess "invalid filename" unless defined(my $filename = sanity_relative_filename($e->{relfilename}));
		$self->_write_line("A\t$e->{time}\tDELETED\t$e->{archive_id}\t$filename");
	} elsif ($e->{type} eq 'RETRIEVE_JOB') {
		#  RETRIEVE_JOB $data->{archive_id}
		defined( $e->{$_} ) || confess "bad $_" for (qw/archive_id job_id/);
		$self->_write_line("A\t$e->{time}\tRETRIEVE_JOB\t$e->{archive_id}\t$e->{job_id}");
	} else {
		confess "Unexpected else";
	}
}

sub _write_line
{
	my ($self, $line) = @_;
  	open (F, ">>:encoding(UTF-8)", $self->{journal_file}) || croak;
	print F $line."\n";
	close F;
	# TODO: fsync()
}

#
# Reading file listing
#

sub read_all_files
{
	my ($self) = @_;
	$self->{allfiles_a} = $self->_read_files('all');
}

sub read_new_files
{
	my ($self, $max_number_of_files) = @_;
	$self->{newfiles_a} = $self->_read_files('new', $max_number_of_files);
}

sub read_existing_files
{
	my ($self) = @_;
	$self->{existingfiles_a} = $self->_read_files('existing');
}


sub _read_files
{
	my ($self, $mode, $max_number_of_files) = @_;
	
	confess unless defined($self->{root_dir});
	my $filelist = [];
	my $i = 0;
	# TODO: find better workaround than "-s"
	$File::Find::prune = 0;
	File::Find::find({ wanted => sub {
		if ($max_number_of_files && (scalar @$filelist >= $max_number_of_files)) {
			$File::Find::prune = 1;
			return;
		}
		
		if (++$i % 1000 == 0) {
			print "Found $i local files\n";
		}
		
		my $filename = $_;
		if ($self->_is_file_exists($filename)) {
			my ($absfilename, $relfilename) = ($_, File::Spec->abs2rel($filename, $self->{root_dir}));
			
			if ($self->_can_read_filename_for_mode($relfilename, $mode)) {
				my $relfilename = File::Spec->abs2rel($filename, $self->{root_dir});
				confess "invalid filename" unless defined($relfilename = sanity_relative_filename($relfilename));
				push @$filelist, { absfilename => $filename, relfilename => $relfilename };
			}
		}
	}, preprocess => sub {
		map { decode("UTF-8", $_, 1) } @_;
	}, no_chdir => 1 }, ($self->{root_dir}));
	
	$filelist;
}

sub absfilename
{
	my ($self, $relfilename) = @_;
	confess unless defined($self->{root_dir});
	return File::Spec->rel2abs($relfilename, $self->{root_dir});
}

# Class method
# Does not work with directory names
sub sanity_relative_filename
{
	my ($filename) = @_;
	return undef if $filename =~ m!^//!g;
	$filename =~ s!^/!!;
	return undef if $filename =~ m![\r\n\t]!g;
	$filename = File::Spec->catdir( map {return undef if m!^\.\.?$!; $_; } split('/', File::Spec->canonpath($filename)) );
	return undef if $filename eq '';
	return $filename;
}

sub _is_file_exists
{
	my ($self, $filename) = @_;
	(-f $filename) && (-s $filename);
}

sub _can_read_filename_for_mode
{
	my ($self, $relfilename, $mode) = @_;
	my $ok = 0;
	if ($mode eq 'all') {
		$ok = 1;
	} elsif ($mode eq 'new') {
		if (!defined($self->{journal_h}->{$relfilename})) {
			$ok = 1;
		} else {
			print "Skip $relfilename\n";
		}
	} elsif ($mode eq 'existing') {
		if (defined($self->{journal_h}->{$relfilename})) {
			$ok = 1;
		} else {
			print "Not exists $relfilename\n";
		}
	}
	$ok;
}





1;
