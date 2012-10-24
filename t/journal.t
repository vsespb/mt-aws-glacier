#!/usr/bin/perl

use strict;
use warnings;
use Test::Simple tests => 28;
use lib qw/../;
use Journal;
use File::Path qw(make_path remove_tree);
use TreeHash;

my $mtroot = '/tmp/mt-aws-glacier-tests';
my $tmproot = "$mtroot/journal-1";
my $dataroot = "$tmproot/dataL1/dataL2";
my $journal_file = "$tmproot/journal";

remove_tree($tmproot) if ($tmproot) && (-d $tmproot);
make_path($dataroot);


my $testfiles = [
{ type => 'dir', filename => 'dirA' },
{ type => 'normalfile', filename => 'dirA/file1', content => 'dAf1a', journal => 'created' },
{ type => 'normalfile', filename => 'dirA/file2', content => 'dAf2aa'},
{ type => 'dir', filename => 'dirB' },
{ type => 'normalfile', filename => 'dirB/file1', content => 'dBf1aaa' , journal => 'created'},
{ type => 'normalfile', filename => 'dirB/file2', content => 'dBf2aaaa' , journal => 'created'},
{ type => 'dir', filename => 'dirB/dirB1' },
{ type => 'normalfile', filename => 'dirB/dirB1/file1', content => 'dB1f1bbbba'},
{ type => 'normalfile', filename => 'dirB/dirB1/file2', content => 'dB1f2bbbbaa' , journal => 'created'},

];


#my $journals = {};
#for (qw/1/) {
#	$journals->{$_} = "$tmpdir/journals/journal$_";
#	system("cp journal$_ $journals->{$_}");
#}

# creating files

for my $testfile (@$testfiles) {
	$testfile->{fullname} = "$dataroot/$testfile->{filename}";
	if ($testfile->{type} eq 'dir') {
		make_path($testfile->{fullname});
	} elsif ($testfile->{type} eq 'normalfile') {
		open F, ">$testfile->{fullname}";
		print F $testfile->{content};
		close F;
	}
}

# creating journal for v0.7beta

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


my $j = Journal->new(journal_file => $journal_file, root_dir => $dataroot);
$j->read_journal();
$j->read_all_files();


{
	my @checkfiles = grep { $_->{type} ne 'dir' } @$testfiles;
	ok((scalar @checkfiles) == scalar @{$j->{allfiles_a}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{allfies_a}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
}

{
	my @checkfiles = grep { $_->{type} eq 'normalfile' && $_->{journal} && $_->{journal} eq 'created' } @$testfiles;
	ok(( scalar @checkfiles == scalar keys %{ $j->{journal_h} } ), "journal - number of planed and real files match");
	
	for my $cf (@checkfiles) {
		ok (my $jf = $j->{journal_h}->{$cf->{filename}}, "file $cf->{filename} exists in Journal");
		ok ($jf->{size} == $cf->{filesize}, "file size match $jf->{size} == $cf->{filesize}");
		ok ($jf->{treehash} eq $cf->{final_hash}, "treehash matches"	);
		ok ($jf->{archive_id} eq $cf->{archive_id}, "archive id matches"	);
		ok ($jf->{absfilename} eq File::Spec->rel2abs($cf->{filename}, $dataroot), "absfilename match"); # actually better test in real
	}
}

remove_tree($tmproot) if ($tmproot) && (-d $tmproot);

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
