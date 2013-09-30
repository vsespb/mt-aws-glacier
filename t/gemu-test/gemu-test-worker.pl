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
use Capture::Tiny qw/capture_merged/;
use Fcntl qw/LOCK_SH LOCK_EX LOCK_NB LOCK_UN/;
use File::Copy;
use File::Compare;

our $BASE_DIR='/dev/shm/mtaws';
our $DIR;
our $GLACIER='../../../src/mtglacier';
our $N;
our $VERBOSE = 0;
our $FASTMODE = 0;
our $PPID = $$;
our $GLOBAL_DIR = "$BASE_DIR/$PPID";

our $DEFAULT_PARTSIZE = 64;

our $data;
our $_current_task;
our $_current_task_stack;
our $_global_cache = {};

GetOptions ("n=i" => \$N, 'verbose' => \$VERBOSE, 'fastmode' => \$FASTMODE);
$N ||= 1;

$ENV{MTGLACIER_FAKE_HOST}='127.0.0.1:9901';

binmode STDOUT, ":encoding(UTF-8)";
binmode STDIN, ":encoding(UTF-8)";


sub getlock
{
	local $@;
	my $filename = "$GLOBAL_DIR/".shift().".lock";
	open my $f, ">", $filename or confess "$filename $!";
	flock $f, LOCK_EX or confess;
	my (@res_a, $res);
	if (wantarray) {
		@res_a = shift->();
	} else {
		$res = shift->();
	}
	flock $f, LOCK_UN or confess;
	close $f;
	return wantarray ? @res_a : $res;
}

sub lock_screen
{
	getlock "screen", shift;
}


sub print_current_task
{
	for (@_) {
		print "\$ $_->{cmd}\n";
		print "$_->{output}\n";
	}
}

sub with_task
{
	local $_current_task_stack = [];
	local $_current_task = shift;
	eval {
		alarm 180;
		shift->();
		alarm 0;
	1; } or do {
		alarm 0;
		lock_screen sub {
			print "# FAILED $_current_task\n";
			print_current_task @$_current_task_stack;
		};
		die $@;
	};
	lock_screen sub {
		print "# OK $_current_task\n";
		print_current_task @$_current_task_stack if $VERBOSE;
	};
}

sub push_command
{
	confess unless $_current_task_stack;
	push @$_current_task_stack, { cmd => shift, output => shift };
}

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
		confess Dumper [$key, $data];
	}
};

sub get_or_undef($)
{
	eval { get(shift);};
}


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
	my $content = shift;
	my $srcfilename = get_sample_fullname($content);
	return cached("$srcfilename.treehash", sub {
		my $part_th = App::MtAws::TreeHash->new();
		open my $f, "<", $srcfilename or confess;
		binmode $f;
		$part_th->eat_file($f);
		close $f;
		$part_th->calc_tree();
		$part_th->get_final_hash();
	});
}

sub create_file
{
	my ($filenames_encoding, $root, $relfilename, $content, %args) = (shift, shift, shift, pop, @_);

	my $fullname = "$root/$relfilename";
	my $binaryfilename = encode($filenames_encoding, $fullname, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	mkpath(dirname($binaryfilename));

	my $srcfilename = get_sample_fullname($content);
	copy($srcfilename, $binaryfilename) or confess;
	confess if -s $srcfilename != -s $binaryfilename;
	utime $args{mtime}, $args{mtime}, $binaryfilename or confess if defined($args{mtime});
}

sub check_file
{
	my ($filenames_encoding, $root, $relfilename, $content, %args) = (shift, shift, shift, pop, @_);
	confess unless $content;
	my $fullname = "$root/$relfilename";
	my $binaryfilename = encode($filenames_encoding, $fullname, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);

	my $srcfilename = get_sample_fullname($content);
	return compare($srcfilename, $binaryfilename) == 0;
}

sub create_journal
{
	my ($journal_fullname, $relfilename, $content, %args) = (shift, shift, pop, @_);
	open(my $f, ">encoding(UTF-8)", $journal_fullname) or confess;
	my $archive_id = gen_archive_id;
	my $treehash = treehash($content);
	$args{mtime} = 123 unless defined $args{mtime};
	print $f "A\t456\tCREATED\t$archive_id\t".(-s get_sample_fullname($content))."\t$args{mtime}\t$treehash\t$relfilename\n";
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
protocol=http
END
		close $f;
}


sub cmd
{
	my (@args) = @_;
	my ($merged, $res, $exitcode);
	{
		local $SIG{__WARN__} = sub {};
		($merged, $res, $exitcode) = capture_merged {
			(system(@args), $?);
		};
	}
	#print $merged;
	push_command(join(" ", @args), $merged);
	die "mtlacier exited after SIGINT" if $exitcode==2;
	return ($res, $merged);
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
	cmd($perl, $glacier, $command, @$args, @opts_e);#'-MDevel::Cover',
}


sub run_ok
{
	my ($code, $out) = run(@_);
	confess if $code;
	#confess unless $out =~ /^OK DONE/m;
	$out
}

sub run_fail
{
	my ($code, $out) = run(@_);
	confess unless $code;
	$out
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

sub get_sample_fullname
{
	"$GLOBAL_DIR/".shift;
}

sub memory_cached
{
	my ($id, $cb) = @_;
	defined $_global_cache->{$id} ? $_global_cache->{$id} : $_global_cache->{$id} = $cb->();
}

sub file_cached
{
	my ($filename, $cb) = @_;
	getlock("$filename.lock", sub {
		if (-e $filename) {
			open my $f, "<", $filename or confess $!;
			binmode $f;
			my $data = do { local $/; <$f> }; # BINARY ONLY
			close $f;
			return $data;
		} else {
			print STDERR "WR $filename\n";
			open my $f, ">", $filename or confess $!;
			binmode $f;
			my $data = $cb->();
			print $f $data;
			close $f;
			return $data;
		}
	});
}

sub cached
{
	my ($filename, $cb) = @_;
	print STDERR "C $filename\n";
	memory_cached($filename, sub {
		file_cached($filename, $cb);
	});
}

sub writing_sample_file($&)
{
	my ($name, $cb) = @_;
	my $filename = get_sample_fullname($name);
	getlock("sample-files-$name", sub {
		unless (-e $filename) {
			open my $f, ">", $filename or confess;
			binmode $f;
			$cb->($f);
			close $f;
		}
		return $name;
	});
}

sub get_file_body
{
	my ($file_body_type, $filesize) = @_;
	confess if $file_body_type eq 'zero' && $filesize != 1;
	my $name = "ok_${file_body_type}_$filesize";
	return writing_sample_file $name, sub {
		my ($f) = @_;
		if ($file_body_type eq 'zero') {
			print ($f '0') or confess $!;
		} else {
			for (1..$filesize) {
				print($f "x") or confess $!;
			}
		}
	};
}

sub get_first_file_body
{
	my ($file_body_type, $filesize) = @_;
	my $name = "first_${file_body_type}_$filesize";
	return writing_sample_file $name, sub {
		my ($f) = @_;
		for (1..$filesize) {
			print($f "Z") or confess $!;
		}
	};
}

sub gen_otherfiles
{
	my ($bigfile);
	return unless get_or_undef('otherfiles');
	my @sizes = ( (otherfiles_size()) x otherfiles_count());
	push @sizes, ( (otherfiles_big_size()) x otherfiles_big_count()) if otherfiles_big_count() > 0;
	my $i = 0;
	map {
		++$i;
		{ file_id => get_first_file_body('normal', $_), dest_filename => "otherfile$i" };
	} @sizes;
}

sub create_otherfiles
{
	my ($filenames_encoding, $root_dir) = @_;
	my @otherfiles = gen_otherfiles();
	for (@otherfiles) {
		create_file($filenames_encoding, $root_dir, $_->{dest_filename}||confess, $_->{file_id}||confess);
	}
	@otherfiles;
}

sub check_otherfiles
{
	my ($filenames_encoding, $root_dir, @otherfiles) = @_;
	for (@otherfiles) {
		confess "$_->{dest_filename} $_->{file_id}" unless check_file($filenames_encoding, $root_dir, $_->{dest_filename}||confess, $_->{file_id}||confess);
	}
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

	my @otherfiles = create_otherfiles(filenames_encoding(), $root_dir);

	{
		local $ENV{NEWFSM}=$ENV{USENEWFSM};
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
	}

	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

	empty_dir $root_dir;

	$opts{'max-number-of-files'} = 100_000;
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/]);

	check_otherfiles(filenames_encoding(), $root_dir, @otherfiles) if @otherfiles && $FASTMODE < 3;
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
	my $new_journal_fullname = "$DIR/${journal_name}.new";

	my $content = get_file_body(filebody(), filesize());

	my ($file_mtime, $journal_mtime, $journal_content, $is_treehash, $is_upload, $detect_option) = do {
		my $first_content = get_first_file_body(filebody(), filesize());
		my $DSIZE = get_first_file_body('normal', filesize()+1);
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
	$opts{'terminal-encoding'} = my $terminal_encoding = terminal_encoding();
	$opts{'filenames-encoding'} = filenames_encoding();

	$opts{concurrency} = concurrency();

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);
	empty_dir $root_dir;

	# creating wrong file
	create_file(filenames_encoding(), $root_dir, filename(), mtime => $journal_mtime, $journal_content);
	$opts{partsize} = $DEFAULT_PARTSIZE;
	run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);

	# creating right file
	create_file(filenames_encoding(), $root_dir, filename(), mtime => $file_mtime, $content);

	my @otherfiles = create_otherfiles(filenames_encoding(), $root_dir);

	$opts{partsize} = partsize();
	$opts{'new'}=undef if @otherfiles;
	$opts{'replace-modified'}=undef;
	$opts{'detect'} = $detect_option;
	{
		#local $ENV{NEWFSM}=$ENV{USENEWFSM};
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);

		if ($is_upload) {
			confess unless ($out =~ /\sFinished\s.*\sDeleted\s/s);
		} else {
			confess if ($out =~ /\s(Finished|Deleted)\s/);
		}

		if ($is_treehash) {
			confess unless ($out =~ /\sChecked treehash for\s/);
		} else {
			confess if ($out =~ /\sChecked treehash for\s/);
		}

	}

	if ($FASTMODE < 10) {
		empty_dir $root_dir;
		$opts{'max-number-of-files'} = 100_000;
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/]);

		check_otherfiles(filenames_encoding(), $root_dir, @otherfiles) if @otherfiles && $FASTMODE < 3;
		run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding filenames-encoding/])
			if @otherfiles && $FASTMODE < 5;
		if ($is_upload) {
			confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);
		} else {
			confess unless check_file(filenames_encoding(), $root_dir, filename(), $journal_content);
		}
	}
	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
}


sub process
{
	if (get "command" eq 'sync') {
		if (subcommand() eq 'sync_new') {
			process_sync_new();
		} elsif (subcommand() eq 'sync_modified') {
			process_sync_modified();
		}
	}
}

sub process_task
{
	my ($task) = @_;
	$data = { map { /^([^=]+)=(.+)$/ or confess; $1 => $2; } split ' ', $task };
	with_task $task, sub {
		process();
	};
}

sub get_tasks
{
	my @tasks = map { chomp; $_ } <STDIN>;
	my $i = 0;
    part { $i++ % $N; } @tasks;
}

empty_dir $BASE_DIR;
mkpath $GLOBAL_DIR;

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

$SIG{INT} = sub { print STDERR "SIGINT!\n"; };
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
print STDERR "WARN: PIDs left in list\n" if %pids && $ok;
print STDERR ($ok ? "\n===\n===OK===\n===\n" : "\n===\n===FAIL===\n===\n");
exit($ok ? 0 : 1);

__END__
