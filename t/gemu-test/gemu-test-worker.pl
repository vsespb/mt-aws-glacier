#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use lib '../../lib';
use Data::Dumper;
use Carp;
use File::Basename;
use Encode;
use File::Path qw/mkpath rmtree/;
use Getopt::Long;
use App::MtAws::TreeHash;
use List::MoreUtils qw(part);

our $BASE_DIR='/dev/shm/mtaws';
our $DIR;
our $GLACIER='../../../src/mtglacier';
our $N;

GetOptions ("n=i" => \$N);
$N or confess $N;

$ENV{MTGLACIER_FAKE_HOST}='127.0.0.1:9901';

binmode STDOUT, ":encoding(UTF-8)";
binmode STDIN, ":encoding(UTF-8)";

our $data;

sub get($) {
	my $key = shift;
	confess unless $key;
	confess if $key =~ /\A\-/;
	confess if defined $data->{$key} && defined $data->{"-$key"};
	my $v;
	if (defined ($v = $data->{$key})) {
		$v;
	} elsif (defined ($v = $data->{"-$key"})) {
		$v;
	} else {
		confess [$key, Dumper $data];
	}
};

sub AUTOLOAD
{
	use vars qw/$AUTOLOAD/;
	$AUTOLOAD =~ s/^.*:://;
	get("$AUTOLOAD");
};

our $increment = 0;
sub get_uniq_id()
{
	$$."_".(++$increment);
}

sub gen_archive_id
{
	sprintf("%s%05d%08d", "x" x 125, $$, ++$increment);
}

sub treehash
{
	my $part_th = App::MtAws::TreeHash->new();
	$part_th->eat_data($_[0]);
	$part_th->calc_tree();
	$part_th->get_final_hash();
}


sub create_file
{
	my ($filenames_encoding, $root, $relfilename) = (shift, shift, shift);
	confess unless defined $_[0];

	my $fullname = "$root/$relfilename";
	my $binaryfilename = encode($filenames_encoding, $fullname, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	mkpath(dirname($binaryfilename));
	open (my $F, ">", $binaryfilename) or confess;
	binmode $F;
	print $F $_[0];
	close $F;
}

sub check_file
{
	my ($filenames_encoding, $root, $relfilename) = (shift, shift, shift);
	my $fullname = "$root/$relfilename";
	my $binaryfilename = encode($filenames_encoding, $fullname, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	open (my $F, "<", $binaryfilename) or return 0;
	binmode $F;
	read $F, my $buf, -s $F;
	return 0 if $buf ne $_[0];
	return 1;
}

sub create_journal
{
	my ($journal_fullname, $relfilename) = (shift, shift);
	open(my $f, ">", $journal_fullname) or confess;
	my $archive_id = gen_archive_id;
	my $treehash = treehash($_[0]);
	print $f "A\t456\tCREATED\t$archive_id\t".length($_[0])."\t123\t$treehash\t$relfilename\n";
	close $f;
}

sub create_config
{
		my ($file, $terminal_encoding) = @_;
		open (my $f, ">", encode($terminal_encoding, $file||die, Encode::DIE_ON_ERR|Encode::LEAVE_SRC))||confess "$file $!";
		print $f <<"END";
key=AKIAJ2QN54K3SOFABCDE
secret=jhuYh6d73hdhGndk1jdHJHdjHghDjDkkdkKDkdkd
# eu-west-1, us-east-1 etc
#region=eu-west-1
region=us-east-1
protocol=https
END
		close $f;
}


sub cmd
{
	print ">>", join(" ", @_), "\n";
	my $res = system(@_);
	die if $?==2;
	$res;
}

sub run
{
	my ($terminal_encoding, $perl, $glacier, $command, $opts, $optlist, $args) = @_;
	my %opts;
	if ($optlist) {
		$opts{$_} = $opts->{$_} for (@$optlist);
	} else {
		%opts = %$opts;
	}

	my @opts = map { my $k = $_; ref $opts{$k} ? (map { ("-$k" => $_) } @{$opts{$_}}) : ( defined($opts{$k}) ? ("-$k" => $opts{$k}) : "-$k")} keys %opts;
	my @opts_e = map { encode($terminal_encoding, $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC) } @opts;
	cmd($perl, $glacier, $command, @$args, @opts_e);
}

sub run_ok
{
	confess if run(@_);
}

sub run_fail
{
	confess unless run(@_);
}

sub empty_dir
{
	my $dir = shift;
	rmtree $dir if -d $dir;
	mkpath $dir;

}


sub get_filter
{
	my ($match_type, $relfilename) = @_;
	my @filter;
	if ($match_type eq 'match') {
		@filter = ("+$relfilename", "-");
	} elsif ($match_type eq 'nomatch') {
		@filter = ("-$relfilename");
	} elsif (match_filter_type() ne 'default') {
		confess;
	}
	@filter;
}

sub get_file_body
{
	my ($file_body_type, $filesize) = @_;
	confess if $file_body_type eq 'zero' && $filesize != 1;
	$file_body_type eq 'zero' ? '0' : 'x' x $filesize;
}

sub get_first_file_body
{
	my ($file_body_type, $filesize) = @_;
	'Z' x $filesize;
}

sub process_sync_new
{
	empty_dir $DIR;

	my %opts;
	$opts{vault} = "test".get_uniq_id;
	$opts{dir} = my $root_dir = "$DIR/root";


	my $content = get_file_body(filebody(), filesize());
	#my ($filenames_encoding, $root, $relfilename) = (shift, shift, shift);
	create_file(filenames_encoding(), $root_dir, filename(), $content);

	my $journal_name = 'journal';
	my $journal_fullname = "$DIR/$journal_name";
	$opts{journal} = $journal_fullname;

	#create_journal($journal_fullname, filename(), $content);

	$opts{'terminal-encoding'} = my $terminal_encoding = terminal_encoding();
	$opts{'filenames-encoding'} = filenames_encoding();

	$opts{concurrency} = concurrency();
	$opts{partsize} = partsize();

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
	{
		local $ENV{NEWFSM}=$ENV{USENEWFSM};
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
	}

	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

	empty_dir $root_dir;

	$opts{'max-number-of-files'} = 100_000;
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/]);
	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

	confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);

	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
}

sub process_sync_modified
{
	empty_dir $DIR;

	my %opts;
	$opts{vault} = "test".get_uniq_id;
	$opts{dir} = my $root_dir = "$DIR/root";






	my $journal_name = 'journal';
	my $journal_fullname = "$DIR/$journal_name";
	$opts{journal} = $journal_fullname;

	my $content = get_file_body(filebody(), filesize());
	my $first_content = get_first_file_body(filebody(), filesize());
	if (detect() eq 'treehash') {
		if (detect_match()) { # treehash-matches
			create_file(filenames_encoding(), $root_dir, filename(), $first_content);
			create_journal($journal_fullname, filename(), $first_content);
		} else { # treehash-nomatch
			create_file(filenames_encoding(), $root_dir, filename(), $content);
			create_journal($journal_fullname, filename(), $content);
		}
	} elsif (detect() eq 'mtime') {
		if (detect_match()) { # mtime-matches
			create_file(filenames_encoding(), $root_dir, filename(), mtime => 888, $content);
			create_journal($journal_fullname, filename(), $content, mtime => 999);
		} else { #mtime-nomatch
			create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $first_content);
			create_journal($journal_fullname, filename(), $content, mtime => 999);
		}
	} elsif (detect() eq 'mtime-and-treehash') {
		if (detect_match()) { # mtime-and-treehash-matches-treehashfail ( mtime-and-treehash-matches-treehashok )
			create_file(filenames_encoding(), $root_dir, filename(), mtime => 888, $first_content);
			create_journal($journal_fullname, filename(), $content, mtime => 999);
		} else { # mtime-and-treehash-nomatch
			create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $first_content);
			create_journal($journal_fullname, filename(), $content, mtime => 999);
		}
	} elsif (detect() eq 'mtime-or-treehash') {
		if (detect_match()) { # mtime-or-treehash-matches
			create_file(filenames_encoding(), $root_dir, filename(), mtime => 888, $content);
			create_journal($journal_fullname, filename(), $content, mtime => 999);
		} else { # mtime-or-treehash-nomatch-treehashok ( mtime-or-treehash-nomatch-treehashfail )
			create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $content); # TODO: another possibility mtime matches, content differs
			create_journal($journal_fullname, filename(), $content, mtime => 999);
		}
	} elsif (detect() eq 'always-positive') {
		if (detect_match()) { # always-positive
			create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $content);
			create_journal($journal_fullname, filename(), $content, mtime => 999);
		} else {
			confess;
		}
	} elsif (detect() eq 'size-only') {
		if (detect_match()) { # size-only-matches
			# create file with different size but same mtime
		} else { # size-only-nomatch
			# create file with same size but different content and mtime
		}
	}

	$opts{'terminal-encoding'} = my $terminal_encoding = terminal_encoding();
	$opts{'filenames-encoding'} = filenames_encoding();

	$opts{concurrency} = concurrency();
	$opts{partsize} = partsize();

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	$opts{'replace-modified'}=undef;

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);
	empty_dir $root_dir;
	create_file(filenames_encoding(), $root_dir, filename(), $content);
	$opts{'detect'}='treehash';
	{
		local $ENV{NEWFSM}=$ENV{USENEWFSM};
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
	}
	empty_dir $root_dir;
	$opts{'max-number-of-files'} = 100_000;
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/]);

	confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);
	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
}


sub process
{
	if (get "command" eq 'sync') {
		if (subcommand() eq 'sync_new') {
			process_sync_new();
		}
	}
}

sub process_task
{
	my ($task) = @_;
	$data = { map { /^([^=]+)=(.+)$/ or confess; $1 => $2; } split ' ', $task };
	process();
}

sub get_tasks
{
	my @tasks = map { chomp; $_ } <STDIN>;
	my $i = 0;
    part { my $z = ($i++) % $N; print "$i, $N, $z\n"; $z } @tasks;
}

my @parts = get_tasks();
confess if @parts > $N;
my %pids;
for my $task (@parts) {
	my $pid = fork();
	if ($pid) {
		$pids{$pid}=1;
	} elsif (defined $pid) {
		$DIR = "$BASE_DIR/$$";
		for (@$task) {
			process_task($_);
		}
		exit(0);
	} else {
		confess $pid;
	}
}

my $ok = 1;
while () {
	my $p = wait();
	last if $p == -1;
	if ($?) {
		$ok = 0;
		kill 'TERM', $_ for keys %pids;
	} else {
		delete $pids{$p};
	}
}
print STDERR ($ok ? "===OK===\n" : "===FAIL===\n");
exit($ok ? 0 : 1);

__END__
