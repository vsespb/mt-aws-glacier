package Journal;

use File::Find ;
use File::Spec;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{journal_file} || die;
    $self->{root_dir} || die;
    $self->{journal_h} = {};
    return $self;
}

# sub read_journal
sub read_journal
{
	my ($self) = @_;
	my $files = {};
	return unless -s $self->{journal_file};
	open F, "<$self->{journal_file}";
	while (<F>) {
		chomp;
		if (/^\d+\s+CREATED\s+(\S+)\s+(\d+)\s+(\S+)\s+(.*?)$/) {
			my ($archive_id, $size, $treehash, $relfilename) = ($1,$2,$3,$4);
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

sub read_real_files
{
	my ($self) = @_;
	my $filelist = [];
	
	# TODO: find better workaround than "-s"
	find(
		{ wanted => sub { push @$filelist, { absfilename => $_, relfilename => File::Spec->abs2rel($_, $self->{root_dir}) } if ( (-f $_) && (-s $_) ); }, no_chdir => 1 },
		($self->{root_dir})
	);
	$self->{realfiles_a} = $filelist;
}

# sub read_real_files
# sub get_files_to_sync

# sub checl_journal

# sub add_entry




1;
