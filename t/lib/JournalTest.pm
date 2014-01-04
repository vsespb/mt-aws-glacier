# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2014  Victor Efimov
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

package JournalTest;

use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::RealBin/../lib";
use App::MtAws::Journal;
use File::Path;
use App::MtAws::TreeHash;
use Test::More;
use Digest::SHA qw/sha256_hex/;
use Encode;
use File::stat;
use Carp;


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	defined($self->{create_journal_version})||confess;
	$self->{filenames_encoding} ||= 'UTF-8';
	$self->{journal_encoding} ||= 'UTF-8';
	$self->{absdataroot} = $self->{dataroot};
	bless $self, $class;
	return $self;
}

sub test_all
{
	my ($self) = @_;

	$self->test(q{test_journal});
	$self->test(q{test_real_files});

	$self->test(q{test_all_files});
	$self->test(q{test_new_files});
	$self->test(q{test_existing_files});
}

sub binarypath
{
	my ($self, $path) = @_;
	encode($self->{filenames_encoding}, $path, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)
}

sub characterpath
{
	my ($self, $path) = @_;
	decode($self->{filenames_encoding}, $path, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)
}

sub test
{
	my ($self, $testname) = @_;

	my $pwd  = Cwd::getcwd();

	mkpath($self->binarypath($self->{absdataroot}));;
	die unless -d $self->binarypath($self->{absdataroot});

	if (defined ($self->{curdir})) {
		mkpath $self->binarypath($self->{curdir});
		$self->{dataroot} = File::Spec->abs2rel($self->{absdataroot}, $self->{curdir});
		chdir $self->binarypath($self->{curdir}) or die "[$self->{dataroot}\t$self->{curdir}]";
	} else {
		chdir $self->binarypath($self->{mtroot}) or die;
	}

	$self->$testname();


	chdir $self->binarypath($pwd) or die;
	-d && rmtree($_) for ($self->binarypath($self->{tmproot}));
}

sub check_absfilename
{
	my ($self, $should_exist, $relfilename, $absfilename) = @_;

	my $absfilename_old = $self->characterpath(File::Spec->rel2abs($self->binarypath($relfilename), $self->binarypath($self->{dataroot})));
	my $absfilename_correct = File::Spec->catfile($self->{dataroot}, $relfilename);
	my $absfilename_wrong = $self->characterpath(File::Spec->abs2rel(File::Spec->rel2abs($self->binarypath($relfilename), $self->binarypath($self->{dataroot}))));

	if ($should_exist) {
		my $ino_old = stat($self->binarypath($absfilename_old))->ino;
		ok $ino_old;
		is stat($self->binarypath($absfilename_correct))->ino, $ino_old;
		is stat($self->binarypath($absfilename_wrong))->ino, $ino_old;
	}

	#TODO: add File::Spec->canonpath() to _correct and fix absfilename_correct=./dirA/file3
	ok $absfilename_old =~ m{^/};

	ok $absfilename !~ m{//};

	ok $absfilename =~ m{^\Q$self->{dataroot}/\E} unless $self->{dataroot} =~ m{^\.(/|$)};
	is ($absfilename, $absfilename_correct, "absfilename match");
}

sub test_journal
{
	my ($self) = @_;
	$self->create_journal();

	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, follow => $self->{follow});
	$j->read_journal(should_exist => 1);

	my @checkfiles = grep { $_->{type} eq 'normalfile' && $_->{journal} && $_->{journal} eq 'created' } @{$self->{testfiles}};
	ok(( scalar @checkfiles == scalar keys %{ $j->{journal_h} } ), "journal - number of planed and real files match");

	for my $cf (@checkfiles) {
		ok (my $jf = $j->{journal_h}->{$cf->{filename}}, "file $cf->{filename} exists in Journal");
		ok ($jf->{size} == $cf->{filesize}, "file size match $jf->{size} == $cf->{filesize}");
		ok ($jf->{treehash} eq $cf->{final_hash}, "treehash matches");
		ok ($jf->{archive_id} eq $cf->{archive_id}, "archive id matches");
		$self->check_absfilename(0, $cf->{filename}, $j->absfilename($cf->{filename}));
	}
}

sub test_real_files
{
	my ($self) = @_;
	$self->create_files();

	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, filter => $self->{filter}, follow => $self->{follow});
	$j->read_files({new=>1,existing=>1});

	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{exclude} } @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{listing}{new}}+scalar @{$j->{listing}{existing}}, "number of planed and real files match");

	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{listing}{new}}, @{$j->{listing}{existing}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
		$self->check_absfilename(1, $realfile->{relfilename}, $j->absfilename($realfile->{relfilename}));
	}
}

sub test_all_files
{
	my ($self) = @_;
	$self->create_journal();
	$self->create_files('skip');
	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, filter => $self->{filter}, follow => $self->{follow});
	$j->read_files({new=>1,existing=>1});

	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} && !$_->{exclude} } @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{listing}{new}}+scalar @{$j->{listing}{existing}}, "number of planed and real files match");

	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{listing}{new}}, @{$j->{listing}{existing}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
}


sub test_new_files
{
	my ($self) = @_;
	$self->create_journal();
	$self->create_files('skip');
	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, filter => $self->{filter}, follow => $self->{follow});#
	$j->read_journal(should_exist => 1);
	$j->read_files({new=>1});
	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} && !$_->{exclude} && (!$_->{journal} || $_->{journal} ne 'created' ) } @{$self->{testfiles}};

	ok((scalar @checkfiles) == scalar @{$j->{listing}{new}}, "number of planned and real files match");

	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{listing}{new}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
}

sub test_existing_files
{
	my ($self) = @_;
	$self->create_journal();
	$self->create_files('skip');
	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, filter => $self->{filter}, follow => $self->{follow});
	$j->read_journal(should_exist => 1);
	$j->read_files({existing=>1});

	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} && !$_->{exclude} && ($_->{journal} && $_->{journal} eq 'created')} @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{listing}{existing}}, "number of planed and real files match");

	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{listing}{existing}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
}

sub create_files
{
	my ($self, $mode) = @_;
	for my $testfile (@{$self->{testfiles}}) {
		$testfile->{fullname} = "$self->{absdataroot}/$testfile->{filename}";
		if ($testfile->{type} eq 'dir') {
			mkpath(encode($self->{filenames_encoding}, $testfile->{fullname}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
		} elsif (($testfile->{type} eq 'normalfile')  && ( #&& !$testfile->{exclude}
			(!defined($mode)) ||
			( ($mode eq 'skip') && !$testfile->{skip} )
			))
		{
			open (F, ">:encoding(UTF-8)", encode($self->{filenames_encoding}, $testfile->{fullname}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
			print F $testfile->{content};
			close F;
		}
	}
}


sub create_journal
{
	my ($self, $mode) = @_;
	if ($self->{create_journal_version} =~ /^[ABC]$/) {
		$self->create_journal_vABC($self->{create_journal_version}, $mode);
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
	open (F, ">:encoding($self->{journal_encoding})", encode($self->{filenames_encoding}, $self->{journal_file}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC)) || confess;
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

# creating journal v 'A'
sub create_journal_vABC
{
	my ($self, $version, $mode) = @_;
	open (F, ">:encoding($self->{journal_encoding})", encode($self->{filenames_encoding}, $self->{journal_file}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
	my $t = time() - (scalar @{$self->{testfiles}})*2;
	my $ft = $t - 1000;
	my $dt = $t + 1;
	for my $testfile (@{$self->{testfiles}}) {
		$ft = $testfile->{mtime} if defined $testfile->{mtime};
		if (($testfile->{type} eq 'normalfile') && $testfile->{journal} && ($testfile->{journal} eq 'created')) {
			$testfile->{archive_id} = get_random_archive_id($t);
			$testfile->{filesize} = length($testfile->{content});
			$testfile->{final_hash} = scalar_treehash(encode_utf8($testfile->{content}));
			print F "$version\t$t\tCREATED\t$testfile->{archive_id}\t$testfile->{filesize}\t$ft\t$testfile->{final_hash}\t$testfile->{filename}\n";
		} elsif (($testfile->{type} eq 'normalfile') && $testfile->{journal} && ($testfile->{journal} eq 'created_and_deleted')) {
			$testfile->{archive_id} = get_random_archive_id($t);
			$testfile->{filesize} = length($testfile->{content});
			$testfile->{final_hash} = scalar_treehash(encode_utf8($testfile->{content}));
			print F "$version\t$t\tCREATED\t$testfile->{archive_id}\t$testfile->{filesize}\t$ft\t$testfile->{final_hash}\t$testfile->{filename}\n";
			print F "$version\t$dt\tDELETED\t$testfile->{archive_id}\t$testfile->{filename}\n";
		}
		$t++;
	}
	close F;
}

our $global_cnt;

sub get_random_archive_id
{
	my ($i) = @_;
	$global_cnt++;
	sha256_hex($$.time().$i.$global_cnt);
}

our %treehash_cache;

sub scalar_treehash
{
	my ($str) = @_;
	confess if utf8::is_utf8($str);
	$treehash_cache{$str} ||= do {
		my $th = App::MtAws::TreeHash->new();
		$th->eat_data(\$str);
		$th->calc_tree();
		$th->get_final_hash();
	}
}

1;
