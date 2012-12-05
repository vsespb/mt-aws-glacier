#!/usr/bin/perl

use strict;
use warnings;
use Test::Simple tests => 43;
use lib qw/../;
use Journal;
use File::Path;
use TreeHash;

my $mtroot = '/tmp/mt-aws-glacier-tests';
my $tmproot = "$mtroot/journal-1";
my $dataroot = "$tmproot/dataL1/dataL2";
my $journal_file = "$tmproot/journal";

rmtree($tmproot) if ($tmproot) && (-d $tmproot);
mkpath($dataroot);


my $testfiles1 = [
{ type => 'dir', filename => 'dirA' },
{ type => 'normalfile', filename => 'dirA/file1', content => 'dAf1a', journal => 'created' },
{ type => 'normalfile', filename => 'dirA/file2', content => 'dAf2aa', skip=>1},
{ type => 'dir', filename => 'dirB' },
{ type => 'normalfile', filename => 'dirB/file1', content => 'dBf1aaa',skip=>1 , journal => 'created'},
{ type => 'normalfile', filename => 'dirB/file2', content => 'dBf2aaaa' , journal => 'created'},
{ type => 'dir', filename => 'dirB/dirB1' },
{ type => 'normalfile', filename => 'dirB/dirB1/file1', content => 'dB1f1bbbba', skip=>1},
{ type => 'normalfile', filename => 'dirB/dirB1/file2', content => 'dB1f2bbbbaa' , journal => 'created'},

];

test_journal($testfiles1);
test_real_files($testfiles1);

test_all_files($testfiles1);
test_new_files($testfiles1);
test_existing_files($testfiles1);

sub test_journal
{
	my ($testfiles) = @_;
	mkpath($dataroot);
	create_journal_v07($testfiles);
	
	my $j = Journal->new(journal_file => $journal_file, root_dir => $dataroot);
	$j->read_journal();
	
	my @checkfiles = grep { $_->{type} eq 'normalfile' && $_->{journal} && $_->{journal} eq 'created' } @$testfiles;
	ok(( scalar @checkfiles == scalar keys %{ $j->{journal_h} } ), "journal - number of planed and real files match");
	
	for my $cf (@checkfiles) {
		ok (my $jf = $j->{journal_h}->{$cf->{filename}}, "file $cf->{filename} exists in Journal");
		ok ($jf->{size} == $cf->{filesize}, "file size match $jf->{size} == $cf->{filesize}");
		ok ($jf->{treehash} eq $cf->{final_hash}, "treehash matches"	);
		ok ($jf->{archive_id} eq $cf->{archive_id}, "archive id matches"	);
		ok ($jf->{absfilename} eq File::Spec->rel2abs($cf->{filename}, $dataroot), "absfilename match"); # actually better test in real
	}
	rmtree($tmproot) if ($tmproot) && (-d $tmproot);
}

sub test_real_files
{
	my ($testfiles) = @_;
	mkpath($dataroot);
	create_files($testfiles);
	
	my $j = Journal->new(journal_file => $journal_file, root_dir => $dataroot);
	$j->read_all_files();
	
	my @checkfiles = grep { $_->{type} ne 'dir' } @$testfiles;
	ok((scalar @checkfiles) == scalar @{$j->{allfiles_a}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{allfiles_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	rmtree($tmproot) if ($tmproot) && (-d $tmproot);
}

sub test_all_files
{
	my ($testfiles) = @_;
	mkpath($dataroot);
	create_journal_v07($testfiles);
	create_files($testfiles);
	
	my $j = Journal->new(journal_file => $journal_file, root_dir => $dataroot);
	$j->read_all_files();
	
	my @checkfiles = grep { $_->{type} ne 'dir' } @$testfiles;
	ok((scalar @checkfiles) == scalar @{$j->{allfiles_a}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{allfiles_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	rmtree($tmproot) if ($tmproot) && (-d $tmproot);
}


sub test_new_files
{
	my ($testfiles) = @_;
	mkpath($dataroot);
	create_journal_v07($testfiles);
	create_files($testfiles);
	my $j = Journal->new(journal_file => $journal_file, root_dir => $dataroot);
	$j->read_journal();
	$j->read_new_files();
	
	my @checkfiles = grep { $_->{type} ne 'dir' && (!$_->{journal} || $_->{journal} ne 'created') } @$testfiles;
	ok((scalar @checkfiles) == scalar @{$j->{newfiles_a}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{newfiles_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	rmtree($tmproot) if ($tmproot) && (-d $tmproot);
}

sub test_existing_files
{
	my ($testfiles) = @_;
	mkpath($dataroot);
	create_journal_v07($testfiles);
	create_files($testfiles);
	my $j = Journal->new(journal_file => $journal_file, root_dir => $dataroot);
	$j->read_journal();
	$j->read_existing_files();
	
	my @checkfiles = grep { $_->{type} ne 'dir' && $_->{journal} && $_->{journal} eq 'created' } @$testfiles;
	ok((scalar @checkfiles) == scalar @{$j->{existingfiles_a}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{existingfiles_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	rmtree($tmproot) if ($tmproot) && (-d $tmproot);
}

sub create_files
{
	my ($testfiles, $mode) = @_;
	for my $testfile (@$testfiles) {
		$testfile->{fullname} = "$dataroot/$testfile->{filename}";
		if ($testfile->{type} eq 'dir') {
			mkpath($testfile->{fullname});
		} elsif (($testfile->{type} eq 'normalfile') && (
		     (!defined($mode)) ||
		     ( ($mode eq 'skip') && !$testfile->{skip} )
		     ))
		{
			open F, ">$testfile->{fullname}";
			print F $testfile->{content};
			close F;
		}
	}
}


# creating journal for v0.7beta
sub create_journal_v07
{
	my ($testfiles, $mode) = @_;
	open F, ">$journal_file";
	my $t = time() - (scalar @$testfiles)*2;
	for my $testfile (@$testfiles) {
		if (($testfile->{type} eq 'normalfile') && $testfile->{journal} && ($testfile->{journal} eq 'created')) {
			$testfile->{archive_id} = get_random_archive_id($t);
			$testfile->{filesize} = length($testfile->{content});
			$testfile->{final_hash} = scalar_treehash($testfile->{content});
			print F $t." CREATED $testfile->{archive_id} $testfile->{filesize} $testfile->{final_hash} $testfile->{filename}\n";
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
