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
	$self->{root_dir} || die;
	$self->{journal_h} = {};
	
	$self->{used_versions} = {};
	$self->{output_version} = '0';
	
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
		$self->_add_file($relfilename, {
			time => $time,
			archive_id => $archive_id,
			size => $size,
			mtime => $mtime,
			treehash => $treehash,
			absfilename => File::Spec->rel2abs($relfilename, $self->{root_dir})
		});
		$self->{used_versions}->{A} = 1;
	} elsif ($line =~ /^A\t(\d+)\tDELETED\t(\S+)\t(.*?)$/) {
		$self->_delete_file($3);
		$self->{used_versions}->{A} = 1;
		
	# Journal version '0'
	
	} elsif ($line =~ /^(\d+)\s+CREATED\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*?)$/) {
		my ($time, $archive_id, $size, $treehash, $relfilename) = ($1,$2,$3,$4,$5);
		#die if $self->{journal_h}->{$relfilename};
		$self->_add_file($relfilename, {
			time => $time,
			archive_id => $archive_id,
			size => $size,
			treehash => $treehash,
			absfilename => File::Spec->rel2abs($relfilename, $self->{root_dir})
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
	if ($e->{type} eq 'CREATED') {
		#" CREATED $archive_id $data->{filesize} $data->{final_hash} $data->{relfilename}"
		defined( $e->{$_} ) || confess "bad $_" for (qw/time archive_id filesize mtime final_hash relfilename/);
		if ($self->{output_version} eq 'A') {
			print "A\t$e->{time}\tCREATED\t$e->{archive_id}\t$e->{filesize}\t$e->{mtime}\t$e->{final_hash}\t$e->{relfilename}";
		} elsif ($self->{output_version} eq '0') {
			print "$e->{time} CREATED $e->{archive_id} $e->{filesize} $e->{final_hash} $e->{relfilename}";
		} else {
			confess "Unexpected else";
		}
	}
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
				push @$filelist, { absfilename => $filename, relfilename => File::Spec->abs2rel($filename, $self->{root_dir}) };
			}
		}
	}, preprocess => sub {
		map { decode("UTF-8", $_, 1) } @_;
	}, no_chdir => 1 }, ($self->{root_dir}));
	
	$filelist;
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
