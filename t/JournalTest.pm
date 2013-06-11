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
use Encode;
use Carp;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    defined($self->{create_journal_version})||confess;
    $self->{filenames_encoding} ||= 'UTF-8';
    $self->{journal_encoding} ||= 'UTF-8';
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
	mkpath(encode($self->{filenames_encoding}, $self->{dataroot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
	$self->create_journal();
	
	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot});
	$j->read_journal(should_exist => 1);
	
	my @checkfiles = grep { $_->{type} eq 'normalfile' && $_->{journal} && $_->{journal} eq 'created' } @{$self->{testfiles}};
	ok(( scalar @checkfiles == scalar keys %{ $j->{journal_h} } ), "journal - number of planed and real files match");
	
	for my $cf (@checkfiles) {
		ok (my $jf = $j->{journal_h}->{$cf->{filename}}, "file $cf->{filename} exists in Journal");
		ok ($jf->{size} == $cf->{filesize}, "file size match $jf->{size} == $cf->{filesize}");
		ok ($jf->{treehash} eq $cf->{final_hash}, "treehash matches"	);
		ok ($jf->{archive_id} eq $cf->{archive_id}, "archive id matches"	);
		is ($j->absfilename($cf->{filename}), File::Spec->rel2abs($cf->{filename}, $self->{dataroot}), "absfilename match"); # actually better test in real
	}
	
	my $tmproot_e = encode($self->{filenames_encoding}, $self->{tmproot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	rmtree($tmproot_e)
		if ($tmproot_e) && (-d $tmproot_e);
}

sub test_real_files
{
	my ($self) = @_;
	mkpath(encode($self->{filenames_encoding}, $self->{dataroot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
	$self->create_files();
	
	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, filter => $self->{filter});
	$j->read_files({new=>1,existing=>1});
	
	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{exclude} } @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{listing}{new}}+scalar @{$j->{listing}{existing}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{listing}{new}}, @{$j->{listing}{existing}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	my $tmproot_e = encode($self->{filenames_encoding}, $self->{tmproot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	rmtree($tmproot_e)
		if ($tmproot_e) && (-d $tmproot_e);
}

sub test_all_files
{
	my ($self) = @_;
	mkpath(encode($self->{filenames_encoding}, $self->{dataroot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
	$self->create_journal();
	$self->create_files('skip');
	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, filter => $self->{filter});
	$j->read_files({new=>1,existing=>1});
	
	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} && !$_->{exclude} } @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{listing}{new}}+scalar @{$j->{listing}{existing}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{listing}{new}}, @{$j->{listing}{existing}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	my $tmproot_e = encode($self->{filenames_encoding}, $self->{tmproot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	rmtree($tmproot_e)
		if ($tmproot_e) && (-d $tmproot_e);
}


sub test_new_files
{
	my ($self) = @_;
	mkpath(encode($self->{filenames_encoding}, $self->{dataroot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
	$self->create_journal();
	$self->create_files('skip');
	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, filter => $self->{filter});#
	$j->read_journal(should_exist => 1);
	$j->read_files({new=>1});
	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} && !$_->{exclude} && (!$_->{journal} || $_->{journal} ne 'created' ) } @{$self->{testfiles}};

	ok((scalar @checkfiles) == scalar @{$j->{listing}{new}}, "number of planned and real files match");

	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{listing}{new}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	my $tmproot_e = encode($self->{filenames_encoding}, $self->{tmproot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	rmtree($tmproot_e)
		if ($tmproot_e) && (-d $tmproot_e);
}

sub test_existing_files
{
	my ($self) = @_;
	mkpath(encode($self->{filenames_encoding}, $self->{dataroot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC));
	$self->create_journal();
	$self->create_files('skip');
	my $j = App::MtAws::Journal->new(journal_encoding => $self->{journal_encoding},
		journal_file => $self->{journal_file}, root_dir => $self->{dataroot}, filter => $self->{filter});
	$j->read_journal(should_exist => 1);
	$j->read_files({existing=>1});
	
	my @checkfiles = grep { $_->{type} ne 'dir' && !$_->{skip} && !$_->{exclude} && ($_->{journal} && $_->{journal} eq 'created')} @{$self->{testfiles}};
	ok((scalar @checkfiles) == scalar @{$j->{listing}{existing}}, "number of planed and real files match");
	
	my %testfile_h = map { $_->{filename } => $_} @checkfiles;
	for my $realfile (@{$j->{listing}{existing}}) {
		ok ( $testfile_h{ $realfile->{relfilename} }, "found file $realfile->{relfilename} exists in planned test file list" );
	}
	my $tmproot_e = encode($self->{filenames_encoding}, $self->{tmproot}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	rmtree($tmproot_e)
		if ($tmproot_e) && (-d $tmproot_e);
}

sub create_files
{
	my ($self, $mode) = @_;
	for my $testfile (@{$self->{testfiles}}) {
		$testfile->{fullname} = "$self->{dataroot}/$testfile->{filename}";
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

# creating journal for v0.7beta
sub create_journal_vA
{
	my ($self, $mode) = @_;
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
	my $th = App::MtAws::TreeHash->new();
	my $s = $$.time().$i;
	$th->eat_data(\$s);
	$th->calc_tree();
	$th->get_final_hash();
}

sub scalar_treehash
{
	my ($str) = @_;
	confess if utf8::is_utf8($str);
	my $th = App::MtAws::TreeHash->new();
	$th->eat_data(\$str);
	$th->calc_tree();
	$th->get_final_hash();
}

1;
