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

package App::MtAws::Journal;

our $VERSION = '1.110';

use strict;
use warnings;
use utf8;


use File::Find;
use File::Spec 3.12;
use Encode;
use Carp;
use IO::Handle;
use App::MtAws::Utils;
use App::MtAws::Exceptions;
use App::MtAws::Filter;
use App::MtAws::FileVersions;

sub new
{
	my ($class, %args) = @_;

	my %checkargs = %args;
	exists $checkargs{$_} && delete $checkargs{$_}
		for qw/root_dir journal_file journal_encoding output_version leaf_optimization use_active_retrievals filter follow/;
	confess "Unknown argument(s) to Journal constructor: ".join(', ', keys %checkargs) if %checkargs; # TODO: test

	my $self = \%args;
	bless $self, $class;

	$self->{journal_encoding} ||= 'UTF-8';

	if (defined $self->{root_dir}) {
		# copied from File::Spec::catfile
		$self->{canon_root_dir} = File::Spec->catdir($self->{root_dir});
		$self->{canon_root_dir} .= "/" unless substr($self->{canon_root_dir},-1) eq "/";
	}

	defined($self->{journal_file}) || confess;
	$self->{journal_h} = {};
	$self->{archive_h} = {};

	$self->{used_versions} = {};
	$self->{output_version} = 'B' unless defined($self->{output_version});
	$self->{last_supported_version} = 'C';
	$self->{first_unsupported_version} = chr(ord($self->{last_supported_version})+1);

	return $self;
}

#
# Reading journal
#

# sub read_journal

sub read_journal
{
	my ($self, %args) = @_;
	confess unless defined $args{should_exist};
	confess unless length($self->{journal_file});
	$self->{last_read_time} = time();
	$self->{active_retrievals} = {} if $self->{use_active_retrievals};

	my $binary_filename = binaryfilename $self->{journal_file};
	if ($args{should_exist} && !-e $binary_filename) {
		confess;
	} elsif (-e $binary_filename) {
		open_file(my $F, $self->{journal_file}, file_encoding => $self->{journal_encoding}, mode => '<') or
			die exception journal_open_error => "Unable to open journal file %string filename% for reading, errno=%errno%",
				filename => $self->{journal_file}, 'ERRNO';
		my $lineno = 0;
		while (!eof($F)) {
			defined( my $line = <$F> ) or confess;
			++$lineno;
			$line =~ s/\r?\n$// or
				die exception journal_format_error => "Invalid format of journal, line %lineno% not fully written", lineno => $lineno;
			$self->process_line($line, $lineno);
		}
		close $F or confess;
	}
	$self->_index_archives_as_files();
	return;
}

sub open_for_write
{
	my ($self) = @_;
	open_file($self->{append_file}, $self->{journal_file}, mode => '>>', file_encoding => $self->{journal_encoding}) or
		die exception journal_open_error => "Unable to open journal file %string filename% for writing, errno=%errno%",
			filename => $self->{journal_file}, 'ERRNO';
	$self->{append_file}->autoflush();
}

sub close_for_write
{
	my ($self) = @_;
	$self->{append_file} or confess;
	close $self->{append_file} or confess;
}

sub process_line
{
	my ($self, $line, $lineno) = @_;
	try_drop_utf8_flag $line;
	my ($ver, $time, $archive_id, $size, $mtime, $treehash, $relfilename, $job_id);
	# TODO: replace \S and \s, make tests for this

	# Journal version 'A', 'B', 'C'
	# 'B' and 'C' two way compatible
	# 'A' is not compatible, but share some common code
	if (($ver, $time, $archive_id, $size, $mtime, $treehash, $relfilename) =
		$line =~ /^([ABC])\t([0-9]{1,20})\tCREATED\t(\S+)\t([0-9]{1,20})\t([+-]?[0-9]{1,20}|NONE)\t(\S+)\t(.*?)$/) {
		confess "invalid filename" unless is_relative_filename($relfilename);

		# here goes difference between 'A' and 'B','C'
		if ($ver eq 'A') {
			confess if $mtime eq 'NONE'; # this is not supported by format 'A'

			# version 'A' produce records with mtime set even when there is no mtime in Amazon metadata
			# (this is possible when archive uploaded by 3rd party program, or mtglacier <= v0.7)
			# we detect this as $archive_id eq $relfilename - this is practical impossible
			# unless such record was created by download-inventory command
			$mtime = undef if ($archive_id eq $relfilename);
		} else {
			$mtime = undef if $mtime eq 'NONE';
		}


		$self->_add_archive({
			relfilename => $relfilename,
			time => $time+0, # numify
			archive_id => $archive_id,
			size => $size+0, # numify
			mtime => defined($mtime) ? $mtime + 0 : undef,
			treehash => $treehash,
		});
		$self->{used_versions}->{$ver} = 1 unless $self->{used_versions}->{$ver};
	} elsif (($ver, $time, $archive_id, $relfilename) = $line =~ /^([ABC])\t([0-9]{1,20})\tDELETED\t(\S+)\t(.*?)$/) {
		$self->_delete_archive($archive_id); # TODO avoid stuff like $1 $2 $3 etc
		$self->{used_versions}->{$ver} = 1 unless $self->{used_versions}->{$ver};
	} elsif (($ver, $time, $archive_id, $job_id) = $line =~ /^([ABC])\t([0-9]{1,20})\tRETRIEVE_JOB\t(\S+)\t(.*?)$/) {
		$self->_retrieve_job($time+0, $archive_id, $job_id);
		$self->{used_versions}->{$ver} = 1 unless $self->{used_versions}->{$ver};

	# Journal version '0'

	} elsif (($time, $archive_id, $size, $treehash, $relfilename) =
		$line =~ /^([0-9]{1,20}) CREATED (\S+) ([0-9]{1,20}) (\S+) (.*?)$/) {
		confess "invalid filename" unless is_relative_filename($relfilename);
		$self->_add_archive({
			relfilename => $relfilename,
			time => $time+0,
			mtime => undef,
			archive_id => $archive_id,
			size => $size+0,
			treehash => $treehash,
		});
		$self->{used_versions}->{0} = 1 unless $self->{used_versions}->{0};
	} elsif ($line =~ /^[0-9]{1,20}\s+DELETED\s+(\S+)\s+(.*?)$/) { # TODO: delete file, parse time too!
		$self->_delete_archive($1);
		$self->{used_versions}->{0} = 1 unless $self->{used_versions}->{0};
	} elsif (($time, $archive_id) = $line =~ /^([0-9]{1,20})\s+RETRIEVE_JOB\s+(\S+)$/) {
		$self->_retrieve_job($time+0, $archive_id);
		$self->{used_versions}->{0} = 1 unless $self->{used_versions}->{0};
	} elsif ( ($line =~ /^([0-9]{1,20}) /) || ($line =~ /^[A-$self->{last_supported_version}]\t/) ) {
		die exception journal_format_error_broken => "Invalid format of journal, line %lineno% is broken: %line%",
			lineno => $lineno, line => hex_dump_string($line);
	} elsif ( ($line =~ /^[$self->{first_unsupported_version}-Z]\t/) ) {
		die exception journal_format_error_future => "Invalid format of journal, line %lineno% is from future version of mtglacier",
			lineno => $lineno;
	} else {
		die exception journal_format_error_unknown => "Invalid format of journal, line %lineno% is in unknown format: %line%",
			lineno => $lineno, line => hex_dump_string($line);
	}
}

sub _add_archive
{
	my ($self, $args) = @_;
	if (!$self->{filter} || $self->{filter}->check_filenames($args->{relfilename})) {
		confess "duplicate entry" if $self->{archive_h}{$args->{archive_id}};
		$self->{archive_h}{$args->{archive_id}} = $args;
	}
}

sub _delete_archive
{
	my ($self, $archive_id) = @_;
	$self->{archive_h}{$archive_id} or confess "archive $archive_id not found in archive_h"; # TODO: put it to backlog, process later?
	delete $self->{archive_h}{$archive_id};
}

sub _add_filename
{
	my ($self, $args) = @_;
	my $relfilename = $args->{relfilename};
	if ($self->{journal_h}{$relfilename}) {
		if (ref $self->{journal_h}{$relfilename} eq ref {}) {
			my $v = App::MtAws::FileVersions->new();
			$v->add($self->{journal_h}{$relfilename});
			$v->add($args);
			$self->{journal_h}{$relfilename} = $v;
		} else {
			$self->{journal_h}{$relfilename}->add($args);
		}
	} else {
		$self->{journal_h}{$relfilename} = $args
	}
}

sub _index_archives_as_files
{
	my ($self) = @_;
	$self->_add_filename($_) for (values %{$self->{archive_h}});
}

sub _retrieve_job
{
	my ($self, $time, $archive_id, $job_id) = @_;
	if ($self->{use_active_retrievals} && $self->{last_read_time} - $time < 24*60*60) { # data is available for appx. 24+4 hours. but we assume 24 hours
		my $r = $self->{active_retrievals};
		if (!$r->{$archive_id} || $r->{$archive_id}->{time} < $time ) {
			$self->{active_retrievals}->{$archive_id} = { time => $time, job_id => $job_id };
		}
	}
}

sub latest
{
	my ($self, $relfilename) = @_;
	my $e = $self->{journal_h}{$relfilename} or confess "$relfilename not found in journal";
	(ref $e eq ref {}) ? $e : $e->latest();
}

#
# Wrting journal
#

sub add_entry
{
	my ($self, $e) = @_;

	confess unless $self->{output_version} eq 'B';

	# TODO: time should be ascending?

	if ($e->{type} eq 'CREATED') {
		#" CREATED $archive_id $data->{filesize} $data->{final_hash} $data->{relfilename}"
		defined( $e->{$_} ) || confess "bad $_" for (qw/time archive_id size treehash relfilename/);
		confess "invalid filename" unless is_relative_filename($e->{relfilename});
		my $mtime = defined($e->{mtime}) ? $e->{mtime} : 'NONE';
		$self->_write_line("B\t$e->{time}\tCREATED\t$e->{archive_id}\t$e->{size}\t$mtime\t$e->{treehash}\t$e->{relfilename}");
	} elsif ($e->{type} eq 'DELETED') {
		#  DELETED $data->{archive_id} $data->{relfilename}
		defined( $e->{$_} ) || confess "bad $_" for (qw/archive_id relfilename/);
		confess "invalid filename" unless is_relative_filename($e->{relfilename});
		$self->_write_line("B\t$e->{time}\tDELETED\t$e->{archive_id}\t$e->{relfilename}");
	} elsif ($e->{type} eq 'RETRIEVE_JOB') {
		#  RETRIEVE_JOB $data->{archive_id}
		defined( $e->{$_} ) || confess "bad $_" for (qw/archive_id job_id/);
		$self->_write_line("B\t$e->{time}\tRETRIEVE_JOB\t$e->{archive_id}\t$e->{job_id}");
	} else {
		confess "Unexpected else";
	}
}

sub _write_line
{
	my ($self, $line) = @_;
	confess unless $self->{append_file};
	confess unless print { $self->{append_file} } $line."\n";
	# TODO: fsync()
}

#
# Reading file listing
#


sub read_files
{
	my ($self, $mode, $max_number_of_files) = @_;

	my %checkmode = %$mode;
	defined $checkmode{$_} && delete $checkmode{$_} for qw/new existing missing/;
	confess "Unknown mode: ".join(';', keys %checkmode) if %checkmode;

	confess unless defined($self->{root_dir});

	my %missing = $mode->{'missing'} ? %{$self->{journal_h}} : ();

	$self->{listing} = { new => [], existing => [], missing => [] };
	my $i = 0;
	# TODO: find better workaround than "-s"
	$File::Find::prune = 0;
	$File::Find::dont_use_nlink = !$self->{leaf_optimization};

	File::Find::find({ wanted => sub {
		if ($self->_listing_exceeed_max_number_of_files($max_number_of_files)) {
			$File::Find::prune = 1;
			return;
		}

		if (++$i % 1000 == 0) {
			print "Found $i local files\n";
		}

		# note that this exception is probably thrown even if a directory below transfer root contains invalid chars
		die exception(invalid_chars_filename => "Not allowed characters in filename: %filename%", filename => hex_dump_string($_))
			if /[\r\n\t]/;

		if (-d) {
			my $dir = character_filename($_);
			$dir =~ s!/$!!; # make sure there is no trailing slash. just in case.
			my $reldir = abs2rel($dir, $self->{root_dir}, allow_rel_base => 1);
			if ($self->{filter} && $reldir ne '.') {
				my ($match, $matchsubdirs) = $self->{filter}->check_dir($reldir."/");
				if (!$match && $matchsubdirs) {
					$File::Find::prune = 1;
				}
			}
		} else {
			# file can be not existing here (i.e. dangling symlink)
			my $filename = character_filename(my $binaryfilename = $_);
			my $orig_relfilename = abs2rel($filename, $self->{root_dir}, allow_rel_base => 1);
			if (!$self->{filter} || $self->{filter}->check_filenames($orig_relfilename)) {
				if ($self->_is_file_exists($binaryfilename)) {
					my $relfilename;
					confess "Invalid filename: ".hex_dump_string($orig_relfilename)
						unless defined($relfilename = sanity_relative_filename($orig_relfilename));
					if (my $use_mode = $self->_can_read_filename_for_mode($orig_relfilename, $mode)) {
						push @{$self->{listing}{$use_mode}}, { relfilename => $relfilename }; # TODO: we can reduce memory usage even more. we don't need hash here probably??
					}
					delete $missing{$relfilename} if ($mode->{missing});
				}
			}
		}
	}, no_chdir => 1, $self->{follow} ? (follow => 1, follow_skip => 2) : () }, (binaryfilename($self->{root_dir})));

	if ($mode->{missing} && !$self->_listing_exceeed_max_number_of_files($max_number_of_files)) {
		for (keys %missing) {
			unless ($self->_is_file_exists(binaryfilename $self->absfilename($_))) {
				push @{$self->{listing}{missing}}, { relfilename => $_ };
				last if $self->_listing_exceeed_max_number_of_files($max_number_of_files);
			}
		}
	}
}

sub _listing_exceeed_max_number_of_files
{
	my ($self, $max_number_of_files) = @_;
	($max_number_of_files && (
		(
			(scalar @{$self->{listing}{new}}) +
			(scalar @{$self->{listing}{existing}}) +
			(scalar @{$self->{listing}{missing}})
		)  >= $max_number_of_files)
	);
}

sub character_filename
{
	my ($binaryfilename) = @_;
	my $filename;
	my $enc = get_filename_encoding();
	die exception invalid_octets_filename => "Invalid octets in filename, does not map to desired encoding %string enc%: %filename%",
		enc => $enc, filename => hex_dump_string($binaryfilename),
		unless (defined($filename = eval { decode($enc, $binaryfilename, Encode::DIE_ON_ERR|Encode::LEAVE_SRC) }));
	$filename;
}

sub _is_file_exists
{
	my ($self, $filename) = @_;
	(-f $filename) && (-s $filename);
}

sub absfilename
{
	my ($self, $relfilename) = @_;
	confess unless defined($self->{canon_root_dir});

	# Originally it was: File::Spec->rel2abs($relfilename, $self->{root_dir});

	# TODO: maybe add File::Spec->canonpath() and fix absfilename_correct=./dirA/file3 ?
	$self->{canon_root_dir}.$relfilename;
}


sub _can_read_filename_for_mode
{
	my ($self, $relfilename, $mode) = @_;

	if (defined($self->{journal_h}->{$relfilename})) {
		if ($mode->{existing}) {
			return 'existing';
		} elsif ($mode->{new}) { # AND not $mode->{existing}
			print "Skip $relfilename\n";
			return 0;
		} else {
			return 0;
		}
	} else {
		if ($mode->{new}) {
			return 'new';
		} elsif ($mode->{existing}) { # AND not $mode->{new}
			print "Not exists $relfilename\n";
			return 0;
		} else {
			return 0;
		}
	}
}



1;
