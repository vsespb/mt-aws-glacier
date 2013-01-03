package JournalTest;

use strict;
use warnings;
use utf8;
use lib qw/../;
use Journal;
use File::Path;
use TreeHash;
use Test::Simple;
use Encode;
use Carp;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    defined($self->{create_journal_version})||confess;
    bless $self, $class;
    return $self;
}

sub test_all
{
	my ($self) = @_;
	$self->test_journal;
	$self->test_real_files;
	
	$self->test_all_files;
	$self->test_new_files;
	$self->test_existing_files;
}

sub test_journal
{
	my ($self) = @_;
	mkpath($self->{dataroot});
	$self->create_journal();
	
	my $j = Journal->new(journal_file => $self->{journal_file}, root_dir => $self->{dataroot});
	$j->read_journal();
	
	my @checkfiles = grep { $_->{type} eq 'normalfile' && $_->{journal} && $_->{journal} eq 'created' } @{$self->{testfiles}};
	ok(( scalar @checkfiles == scalar keys %{ $j->{journal_h} } ), "journal - number of planed and real files match");
	
	for my $cf (@checkfiles) {
		ok (my $jf = $j->{journal_h}->{$cf->{filename}}, "file $cf->{filename} exists in Journal");
		ok ($jf->{size} == $cf->{filesize}, "file size match $jf->{size} == $cf->{filesize}");
		ok ($jf->{treehash} eq $cf->{final_hash}, "treehash matches"	);
		ok ($jf->{archive_id} eq $cf->{archive_id}, "archive id matches"	);
		ok ($j->absfilename($cf->{filename}) eq File::Spec->rel2abs($cf->{filename}, $self->{dataroot}), "absfilename match"); # actually better test in real
	}
	rmtree($self->{tmproot}) if ($self->{tmproot}) && (-d $self->{tmproot});
}

sub test_real_files
{
	my ($self) = @_;
	mkpath($self->{dataroot});
	$self->create_files();
	
	my $j = Journal->new(journal_file => $self->{journal_file}, root_dir => $self->{dataroot});
	$j->read_all_files();
	
	my @checkfiles = grep { $_->{type} ne 'dir' } @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{allfiles_a}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{allfiles_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	rmtree($self->{tmproot}) if ($self->{tmproot}) && (-d $self->{tmproot});
}

sub test_all_files
{
	my ($self) = @_;
	mkpath($self->{dataroot});
	$self->create_journal();
	$self->create_files('skip');
	
	my $j = Journal->new(journal_file => $self->{journal_file}, root_dir => $self->{dataroot});
	$j->read_all_files();
	
	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} } @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{allfiles_a}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{allfiles_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	rmtree($self->{tmproot}) if ($self->{tmproot}) && (-d $self->{tmproot});
}


sub test_new_files
{
	my ($self) = @_;
	mkpath($self->{dataroot});
	$self->create_journal();
	$self->create_files('skip');
	my $j = Journal->new(journal_file => $self->{journal_file}, root_dir => $self->{dataroot});
	$j->read_journal();
	$j->read_new_files();
	
	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} && (!$_->{journal} || $_->{journal} ne 'created' ) } @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{newfiles_a}}, "number of planed and real files match");

	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{newfiles_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	rmtree($self->{tmproot}) if ($self->{tmproot}) && (-d $self->{tmproot});
}

sub test_existing_files
{
	my ($self) = @_;
	mkpath($self->{dataroot});
	$self->create_journal();
	$self->create_files('skip');
	my $j = Journal->new(journal_file => $self->{journal_file}, root_dir => $self->{dataroot});
	$j->read_journal();
	$j->read_existing_files();
	
	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} && ($_->{journal} && $_->{journal} eq 'created')} @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{existingfiles_a}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{existingfiles_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	rmtree($self->{tmproot}) if ($self->{tmproot}) && (-d $self->{tmproot});
}

sub create_files
{
	my ($self, $mode) = @_;
	for my $testfile (@{$self->{testfiles}}) {
		$testfile->{fullname} = "$self->{dataroot}/$testfile->{filename}";
		if ($testfile->{type} eq 'dir') {
			mkpath($testfile->{fullname});
		} elsif (($testfile->{type} eq 'normalfile') && (
		     (!defined($mode)) ||
		     ( ($mode eq 'skip') && !$testfile->{skip} )
		     ))
		{
			open (F, ">:encoding(UTF-8)", $testfile->{fullname});
			print F $testfile->{content};
			close F;
		}
	}
}


sub create_journal
{
	my ($self, $mode) = @_;
	if ($self->{create_journal_version} eq 'A') {
		$self->create_journal_vA($mode);
	} elsif ($self->{create_journal_version} eq '0') {
		$self->create_journal_v0($mode);
	} else {
		confess;
	}
}

# creating journal for v0.7beta
sub create_journal_v0
{
	my ($self, $mode) = @_;
	open (F, ">:encoding(UTF-8)", $self->{journal_file});
	my $t = time() - (scalar @{$self->{testfiles}})*2;
	for my $testfile (@{$self->{testfiles}}) {
		if (($testfile->{type} eq 'normalfile') && $testfile->{journal} && ($testfile->{journal} eq 'created')) {
			$testfile->{archive_id} = get_random_archive_id($t);
			$testfile->{filesize} = length($testfile->{content});
			$testfile->{final_hash} = scalar_treehash(encode_utf8($testfile->{content}));
			print F $t." CREATED $testfile->{archive_id} $testfile->{filesize} $testfile->{final_hash} $testfile->{filename}\n";
		} elsif (($testfile->{type} eq 'normalfile') && $testfile->{journal} && ($testfile->{journal} eq 'created_and_deleted')) {
			$testfile->{archive_id} = get_random_archive_id($t);
			$testfile->{filesize} = length($testfile->{content});
			$testfile->{final_hash} = scalar_treehash(encode_utf8($testfile->{content}));
			print F $t." CREATED $testfile->{archive_id} $testfile->{filesize} $testfile->{final_hash} $testfile->{filename}\n";
			print F ($t+1)." DELETED $testfile->{archive_id} $testfile->{filename}\n";
		}
		$t++;
	}
	close F;
}

# creating journal for v0.7beta
sub create_journal_vA
{
	my ($self, $mode) = @_;
	open (F, ">:encoding(UTF-8)", $self->{journal_file});
	my $t = time() - (scalar @{$self->{testfiles}})*2;
	my $ft = $t - 1000;
	my $dt = $t + 1;
	for my $testfile (@{$self->{testfiles}}) {
		if (($testfile->{type} eq 'normalfile') && $testfile->{journal} && ($testfile->{journal} eq 'created')) {
			$testfile->{archive_id} = get_random_archive_id($t);
			$testfile->{filesize} = length($testfile->{content});
			$testfile->{final_hash} = scalar_treehash(encode_utf8($testfile->{content}));
			print F "A\t$t\tCREATED\t$testfile->{archive_id}\t$testfile->{filesize}\t$ft\t$testfile->{final_hash}\t$testfile->{filename}\n";
		} elsif (($testfile->{type} eq 'normalfile') && $testfile->{journal} && ($testfile->{journal} eq 'created_and_deleted')) {
			$testfile->{archive_id} = get_random_archive_id($t);
			$testfile->{filesize} = length($testfile->{content});
			$testfile->{final_hash} = scalar_treehash(encode_utf8($testfile->{content}));
			print F "A\t$t\tCREATED\t$testfile->{archive_id}\t$testfile->{filesize}\t$ft\t$testfile->{final_hash}\t$testfile->{filename}\n";
			print F "A\t$dt\tDELETED\t$testfile->{archive_id}\t$testfile->{filename}\n";
		}
		$t++;
	}
	close F;
}

sub get_random_archive_id
{
	my ($i) = @_;
	my $th = TreeHash->new();
	my $s = $$.time().$i;
	$th->eat_data(\$s);
	$th->calc_tree();
	$th->get_final_hash();
}

sub scalar_treehash
{
	my ($str) = @_;
	my $th = TreeHash->new();
	$th->eat_data(\$str);
	$th->calc_tree();
	$th->get_final_hash();
}

1;
