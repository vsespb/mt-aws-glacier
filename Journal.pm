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
    
    $self->{output_version} = '0';
    
    return $self;
}

# sub read_journal
sub read_journal
{
	my ($self) = @_;
	my $files = {};
	return unless -s $self->{journal_file};
	open (F, "<:encoding(UTF-8)", $self->{journal_file});
	while (<F>) {
		chomp;
		
		# Journal version 'A'
		
		if (/^A\t(\d+)\tCREATED\t(\S+)\t(\d+)\t(\d+)\t(\S+)\t(.*?)$/) {
			my ($time, $archive_id, $size, $mtime, $treehash, $relfilename) = ($1,$2,$3,$4,$5,$6);
			$self->{journal_h}->{$relfilename} = {
				archive_id => $archive_id,
				size => $size,
				mtime => $mtime,
				treehash => $treehash,
				absfilename => File::Spec->rel2abs($relfilename, $self->{root_dir})
			};
		} elsif (/^A\t(\d+)\tDELETED\t(\S+)\t(.*?)$/) {
			delete $self->{journal_h}->{$2} if $self->{journal_h}->{$2}; # TODO: exception or warning if $files->{$2}
			
		# Journal version '0'
		
		} elsif (/^\d+\s+CREATED\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*?)$/) {
			my ($archive_id, $size, $treehash, $relfilename) = ($1,$2,$3,$4);
#			die if $self->{journal_h}->{$relfilename};
			$self->{journal_h}->{$relfilename} = {
				archive_id => $archive_id,
				size => $size,
				treehash => $treehash,
				absfilename => File::Spec->rel2abs($relfilename, $self->{root_dir})
			};
		} elsif (/^\d+\s+DELETED\s+(\S+)\s+(.*?)$/) {
			delete $self->{journal_h}->{$2} if $self->{journal_h}->{$2}; # TODO: exception or warning if $files->{$2}
		} else {
#			die;
		}
	}
	close F;
	return;
}

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
	find({ wanted => sub {
		if ($max_number_of_files && (scalar @$filelist >= $max_number_of_files)) {
			$File::Find::prune = 1;
			return;
		}
		
		if (++$i % 1000 == 0) {
			print "Found $i local files\n";
		}
		
		my $filename = $_;
		if ( (-f $filename) && (-s $filename) ) {
			my ($absfilename, $relfilename) = ($_, File::Spec->abs2rel($filename, $self->{root_dir}));

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
			
			
			
			push @$filelist, { absfilename => $filename, relfilename => File::Spec->abs2rel($filename, $self->{root_dir}) } if $ok;
			
			
		}
	}, preprocess => sub {
		map { decode("UTF-8", $_, 1) } @_;
	}, no_chdir => 1 }, ($self->{root_dir}));
	
	$filelist;
}





1;
