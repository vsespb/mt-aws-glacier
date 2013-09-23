#!/usr/bin/env perl

use strict;
use warnings;
use v5.10;
use utf8;
use lib '../../lib';
use Data::Dumper;
use Carp;
use File::Basename;
use Encode;
use File::Path qw/mkpath/;
use App::MtAws::TreeHash;


our ($DIR, $ROOT, $VAULT, $JOURNAL, $NEWJOURNAL, $CFG, $GLACIER, $CONC);
$DIR='/dev/shm/mtaws';
$VAULT="test1";
$GLACIER='src/mtglacier';

$ROOT= "$DIR/файлы";
$CFG="$DIR/конфиг.cfg";
$JOURNAL="$DIR/фурнал";
$NEWJOURNAL="$DIR/журнал.новый";
$ENV{MTGLACIER_FAKE_HOST}='127.0.0.1:9901';

our $increment = 0;

my @variants;

sub get($) { die "Unimplemented"; };
sub before($) { die "Unimplemented"; };

sub add(&)
{
	my $type_cb = shift;
	push @variants, $type_cb;
}

sub gen_archive_id
{
	sprintf("%s%08d", "x" x 130, ++$increment);
}

sub treehash
{
	my $part_th = App::MtAws::TreeHash->new();
	$part_th->eat_data($_[0]);
	$part_th->calc_tree();
	$part_th->get_final_hash();
}


sub create_files
{
	my ($filenames_encoding, $root, $files) = @_;
	for my $testfile (@$files) {
		$testfile->{filename} = my $fullname = "$root/$testfile->{relfilename}";
		$testfile->{binaryfilename} = my $binaryfilename = encode($filenames_encoding, $testfile->{filename}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
		mkpath(dirname($binaryfilename));
		open (my $F, ">", $binaryfilename);
		print $F $testfile->{content};
		close $F;
	}
}

sub create_journal
{
	my ($journal_fullname, $files) = @_;
	open(my $f, ">", $journal_fullname) or confess;
	for my $testfile (@$files) {
		if ($testfile->{already_in_journal}) {
			my $archive_id = gen_archive_id;
			my $treehash = treehash($testfile->{content});
			#print $F $t." CREATED $archive_id $testfile->{filesize} $testfile->{final_hash} $testfile->{filename}\n";
			print $f "A\t$456\tCREATED\t$archive_id\t$testfile->{filesize}\t123\t$treehash\t$testfile->{filename}\n";
		}
	}
	close $f;
}


sub process_one
{
	my ($data) = @_;
	return if ($data->{filesize} > 1 && $data->{filename} ne 'default');

	print join(" ", map { "$_=$data->{$_}" } sort keys %$data), "\n";

	my $filenames_encoding = 'UTF-8';

	my $root_dir = "$DIR/root";

	my @create_files;
	if ($data->{filename} eq 'zero') {
		push @create_files, '0';
	} else {
		push @create_files, 'somefile';
	}

	my $filebody = $data->{filebody} or confess;
	my $filesize = $data->{filesize};

	confess if $filebody eq 'zero' && $filesize != 1;

	my $files = [map {
		{ relfilename => $_, filesize => $filesize, content => $filebody eq 'zero' ? '0' : 'x'x$filesize }
	} @create_files];
	create_files($filenames_encoding, $root_dir, $files);

	my @opts;
	my $journal_name = do {
		if ($data->{journal_name} eq 'default') {
			"journal"
		} elsif ($data->{journal_name} eq 'russian') {
			"журнал";
		} else {
			confess "no journal name";
		}
	};
	my $journal_fullname = "$DIR/$journal_name";
	push @opts,(q{--journal}, $journal_fullname);


	if ($data->{journal_match} eq 'match') {
		$_->{already_in_journal} = 1 for @$files;
	}
	create_journal($journal_fullname, $files);

	my @filter;
	if ($data->{match_filter} eq 'match') {
		@filter = ((map { "+$_" } @create_files), "-");
	} elsif ($data->{match_filter} eq 'nomatch') {
		@filter = ((map { "-$_" } @create_files));
	} elsif ($data->{match_filter} eq 'default') {

	} else {
		confess;
	}

	if ($data->{sync_mode} eq 'sync-new') {
		push @opts, q{--new};
	} elsif ($data->{sync_mode} eq 'sync-modified') {
		push @opts, q{--replace-modified};
	} elsif ($data->{sync_mode} eq 'sync-removed') {
		push @opts, q{--delete-removed};
	}
	push @opts, map { ("--filter", $_) } @filter;
	print "# sync ";
	print join(" ", @opts), "\n";

}

sub process_recursive
{
	my ($data, @variants) = @_;
	if (@variants) {
		my $v = shift @variants;
		no warnings 'redefine';
		local *get = sub($) {
			$data->{+shift} // confess;
		};
		local *before = sub($) {
			confess "use before $_[0]" if defined $data->{$_[0]};
		};
		my ($type, @vals) = $v->($data);
		for (@vals) {
			process_recursive({%$data, $type => $_}, @variants);
		}
	} else {
		#print Dumper $data;

		process_one($data);
	}
}

sub process
{
	process_recursive({}, @variants);
}

add(sub { journal_name => qw/default russian/ });
add(sub { filename => qw/zero default russian latin1/ });
add(sub { filesize => qw/0 1 1048576/ });
add(sub { filebody => (get "filesize" == 1) ? qw/normal zero/ : 'normal' });
add(sub { otherfiles => qw/none many huge/ });
add(sub { sync_mode => qw/sync-new sync-modified sync-deleted/ });
add(sub { journal_match => qw/match nomatch/ });
add(sub { match_filter => qw/default/ });#match nomatch

#return if ($data->{filebody} eq 'zero' && $data->{filesize} ne 1);

#my $filename = sub { filename => qw/zero default russian latin1/ };
#my $filebody = sub { filebody => $data{filesize} == 1 ? qw/normal zero/ : 'normal' };


process

__END__

(relfilename is "0")
	(sync-new sync-modified sync-deleted)
		if sync-new: (match, not-match)
			(match-filter not-match-filter)
