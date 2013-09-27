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
	$part_th->eat_data(shift);
	$part_th->calc_tree();
	$part_th->get_final_hash();
}

sub create_file
{
	my ($filenames_encoding, $root, $relfilename, $content, %args) = (shift, shift, shift, pop, @_);

	my $fullname = "$root/$relfilename";
	my $binaryfilename = encode($filenames_encoding, $fullname, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	mkpath(dirname($binaryfilename));
	open (my $F, ">", $binaryfilename) or confess;
	binmode $F;
	print $F $$content;
	close $F;
}

sub check_file
{
	my ($filenames_encoding, $root, $relfilename, $content, %args) = (shift, shift, shift, pop, @_);
	my $fullname = "$root/$relfilename";
	my $binaryfilename = encode($filenames_encoding, $fullname, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	open (my $F, "<", $binaryfilename) or return 0;
	binmode $F;
	read $F, my $buf, -s $F;
	return 0 if $buf ne $$content;
	return 1;
}

sub create_journal
{
	my ($journal_fullname, $relfilename, $content, %args) = (shift, shift, pop, @_);
	open(my $f, ">", $journal_fullname) or confess;
	my $archive_id = gen_archive_id;
	my $treehash = treehash($content);
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
	my $body = $file_body_type eq 'zero' ? '0' : 'x' x $filesize;
	\$body;
}

sub get_first_file_body
{
	my ($file_body_type, $filesize) = @_;
	my $body = 'Z' x $filesize;
	\$body;
}

sub set_vault
{
	my ($opts) = @_;
	$opts->{vault} = "test".get_uniq_id;
}

sub process_sync_new
{
	empty_dir $DIR;

	my %opts;
	set_vault \%opts;
	$opts{dir} = my $root_dir = "$DIR/root";


	my $content = get_file_body(filebody(), filesize());
	create_file(filenames_encoding(), $root_dir, filename(), $content);

	my $journal_name = 'journal';
	my $journal_fullname = "$DIR/$journal_name";
	$opts{journal} = $journal_fullname;

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

	confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);

	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
}

sub process_sync_modified
{
	empty_dir $DIR;

	my %opts;
	set_vault \%opts;
	$opts{dir} = my $root_dir = "$DIR/root";




	my $journal_name = 'journal';
	my $journal_fullname = "$DIR/$journal_name";
	$opts{journal} = $journal_fullname;

	my $content = get_file_body(filebody(), filesize());

	my ($file_mtime, $journal_mtime, $journal_content, $is_treehash, $is_upload, $detect_option) = do {
		my $first_content = get_first_file_body(filebody(), filesize());
		my $DSIZE = undef;
		my $WRONG = $first_content;
		my $RIGHT = $content;
		use constant A => 1380302319;
		use constant B => A+1;
		use constant WILL_TREEHASH => 1;
		use constant   NO_TREEHASH => 0;
		use constant WILL_UPLOAD => 1;
		use constant   NO_UPLOAD => 0;
		my $cbs = {
			'treehash-matches'                            => sub { (A, A, $WRONG, WILL_TREEHASH, WILL_UPLOAD, 'treehash') },
			'treehash-nomatch'                            => sub { (A, A, $RIGHT, WILL_TREEHASH,   NO_UPLOAD, 'treehash') },
			'mtime-matches'                               => sub { (A, B, $RIGHT,   NO_TREEHASH, WILL_UPLOAD, 'mtime') },
			'mtime-nomatch'                               => sub { (B, B, $WRONG,   NO_TREEHASH,   NO_UPLOAD, 'mtime') },
			'mtime-and-treehash-matches-treehashfail'     => sub { (A, B, $WRONG, WILL_TREEHASH, WILL_UPLOAD, 'mtime-and-treehash') },
			'mtime-and-treehash-matches-treehashok'       => sub { (A, B, $RIGHT, WILL_TREEHASH,   NO_UPLOAD, 'mtime-and-treehash') },
			'mtime-and-treehash-nomatch'                  => sub { (B, B, $WRONG,   NO_TREEHASH,   NO_UPLOAD, 'mtime-and-treehash') },
			'mtime-or-treehash-matches'                   => sub { (A, B, $RIGHT,   NO_TREEHASH, WILL_UPLOAD, 'mtime-or-treehash') },
			'mtime-or-treehash-nomatch-treehashok'        => sub { (B, B, $RIGHT, WILL_TREEHASH,   NO_UPLOAD, 'mtime-or-treehash') },
			'mtime-or-treehash-nomatch-treehashfail'      => sub { (B, B, $WRONG, WILL_TREEHASH, WILL_UPLOAD, 'mtime-or-treehash') },
			'always-positive'                             => sub { (B, B, $RIGHT,   NO_TREEHASH, WILL_UPLOAD, 'always-positive') },
			'size-only-matches'                           => sub { (A, A, $DSIZE,   NO_TREEHASH, WILL_UPLOAD, 'size-only') },
			'size-only-nomatch'                           => sub { (A, A, $WRONG,   NO_TREEHASH,   NO_UPLOAD, 'size-only') },

			''           => sub { () },
		};

		confess unless $cbs->{detect_case()};
		$cbs->{detect_case()}->();
	};

	create_file(filenames_encoding(), $root_dir, filename(), mtime => $file_mtime, $content);
	create_journal($journal_fullname, filename(), $content, mtime => $journal_mtime, $$journal_content);
	$opts{'detect'} = $detect_option;

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
    part { $i++ % $N; } @tasks;
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
	if (detect_case() eq 'treehash-matches' ) {
		create_file(filenames_encoding(), $root_dir, filename(), $first_content);
		create_journal($journal_fullname, filename(), $first_content);
	} elsif (detect_case() eq 'treehash-nomatch') {
		create_file(filenames_encoding(), $root_dir, filename(), $content);
		create_journal($journal_fullname, filename(), $content);
	} elsif (detect_case() eq 'mtime-matches') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 888, $content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'mtime-nomatch') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $first_content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'mtime-and-treehash-matches-treehashfail') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 888, $first_content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'mtime-and-treehash-matches-treehashok') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 888, $content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'mtime-and-treehash-nomatch') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $first_content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'mtime-or-treehash-matches') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 888, $content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'mtime-or-treehash-nomatch-treehashok') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'mtime-or-treehash-nomatch-treehashfail') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $first_content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'always-positive') {
		create_file(filenames_encoding(), $root_dir, filename(), mtime => 999, $content);
		create_journal($journal_fullname, filename(), $content, mtime => 999);
	} elsif (detect_case() eq 'size-only-matches') {
	} elsif (detect_case() eq 'size-only-nomatch') {
	}
