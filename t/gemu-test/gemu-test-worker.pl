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
use Capture::Tiny qw/capture_merged tee_merged/;
use Fcntl qw/LOCK_SH LOCK_EX LOCK_NB LOCK_UN/;
use File::Copy;
use File::Compare;
use Time::HiRes qw/gettimeofday tv_interval usleep/;

our $BASE_DIR='/dev/shm/mtaws';
our $DIR;
our $GLACIER_BIN;
our $N;
our $VERBOSE = 0;
our $FASTMODE = 0;
our $STATE_FILE = undef;
our $HARDLINKS = 0;
our $PPID = $$;
our $GLOBAL_DIR = "$BASE_DIR/$PPID";

our $DEFAULT_PARTSIZE = 64;
our $DEFAULT_CONCURRENCY = 30;

our $data;
our $_current_task;
our $_current_task_stack;
our $_global_cache = {};

GetOptions ("n=i" => \$N, 'verbose' => \$VERBOSE, 'fastmode' => \$FASTMODE, 'state=s' => \$STATE_FILE, 'hardlinks' => \$HARDLINKS, 'glacierbin=s' => \$GLACIER_BIN);
$N ||= 1;

$ENV{MTGLACIER_FAKE_HOST}='127.0.0.1:9901';

our $GLACIER;
if ( !defined($GLACIER_BIN) ) {
#	confess "specify --glacierbin";
	$GLACIER='../../mtglacier';
} elsif ($GLACIER_BIN eq 'prod') {
	$GLACIER='/opt/mt/mtglacier';
} elsif ($GLACIER_BIN eq 'dev') {
	$GLACIER='../../mtglacier';
} else {
	confess "unknown glacierbin $GLACIER_BIN";
}



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
		alarm 600;
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
	if (defined $STATE_FILE) {
		getlock "state_file", sub {
			open my $f, ">>:encoding(UTF-8)", $STATE_FILE or confess $!;
			print $f $_current_task, "\n";
			close $f or confess $!;
		}
	}
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


sub with_newfsm(&)
{
	local $ENV{NEWFSM}=$ENV{USENEWFSM};
	shift->();
}

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
	if ($HARDLINKS) {
		link($srcfilename, $binaryfilename) or confess;
	} else {
		copy($srcfilename, $binaryfilename) or confess;
	}
	confess if -s $srcfilename != -s $binaryfilename;
	utime $args{mtime}, $args{mtime}, $binaryfilename or confess if defined($args{mtime});
}

sub delete_file
{
	my ($filenames_encoding, $root, $relfilename) = (shift, shift, shift);

	my $fullname = "$root/$relfilename";
	my $binaryfilename = encode($filenames_encoding, $fullname, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	unlink $binaryfilename or confess; # RACE here?
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
		if ($VERBOSE) {
			($merged, $res, $exitcode) = tee_merged sub { (system(@args), $?) }
		} else {
			($merged, $res, $exitcode) = capture_merged sub { (system(@args), $?) }
		}
	}
	confess if $merged =~ /WARNING/;
	push_command(join(" ", @args), $merged);
	die "mtlacier exited after SIGINT" if $exitcode==2;
	return ($res, $merged);
}

sub get_run_array
{
	my ($terminal_encoding, $perl, $glacier, $command, $opts, $optlist, $args) = @_;
	$args ||= [];
	my %opts;
	if ($optlist) {
		$opts{$_} = $opts->{$_} for (@$optlist);
	} else {
		%opts = %$opts;
	}

	my @opts = map { my $k = $_; ref $opts{$k} ? (map { ("-$k" => $_) } @{$opts{$_}}) : ( defined($opts{$k}) ? ("-$k" => $opts{$k}) : "-$k")} keys %opts;
	my @opts_e = map { encode($terminal_encoding, $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC) } @opts;
	($perl, $glacier, $command, @$args, @opts_e);
}

sub run
{
	cmd(get_run_array(@_));
}

sub run_with_pipe
{
	my $cb = shift;
	my @a = get_run_array(@_);

	my ($merged, $res, $exitcode);
	{
		local $SIG{__WARN__} = sub {};
		my $capture_what = sub {
			open (my $f, "|-", @a);
			$cb->($f);
			close($f);
			($?, $?)
		};
		if ($VERBOSE) {
			($merged, $res, $exitcode) = &tee_merged($capture_what);
		} else {
			($merged, $res, $exitcode) = &capture_merged($capture_what);
		}
	}
	confess if $merged =~ /WARNING/;
	push_command(join(" ", @a), $merged);
	die "mtlacier exited after SIGINT" if $exitcode==2;
	return ($res, $merged);
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
				print($f chr(int rand(256))) or confess $!;
			}
			$f->flush();
			confess(-s $f, ",", $filesize) unless -s $f == $filesize;
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
			print($f chr(int rand(256))) or confess $!;
		}
		$f->flush();
		confess(-s $f, ",", $filesize) unless -s $f == $filesize;
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
		{ file_id => get_first_file_body('normal', $_), dest_filename => "otherfile$i" }; # "otherfile" is special name, used in regexps
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

sub check_otherfiles_filenames
{
	my ($out, $filename, $otherfiles_ref, $lines_re, $is_relative) = @_;

	my $is_ascii = $filename =~ /^[\x01-\x7f]+$/;

	my $files = 0;
	my @otherfileids;
	for (split ("\n", $out)) {
		if (my ($fullfilename) = $_ =~ $lines_re) {#/^Will UPLOAD (.*)$/
			die if $is_ascii && !$is_relative & !-f $fullfilename;
			$files++;
			if ($fullfilename =~ m{otherfile(\d+)}) {
				push @otherfileids, $1;
			} elsif ($is_ascii) {
				if ($is_relative) {
					die "[$fullfilename] eq [$filename]" unless $fullfilename eq $filename;
				} else {
					my ($shortname) = $fullfilename =~ m{/([^/]+)$};
					die "$shortname eq $filename" unless $shortname eq $filename;
				}
			}
		}
	};
	confess $files unless $files == @$otherfiles_ref + 1;
	my %othefileids = map { $_ => 1 } @otherfileids;
	delete $othefileids{$_} for (1..@$otherfiles_ref);
	die if %othefileids;
}

sub set_vault
{
	my ($opts) = @_;
	$opts->{vault} = "test".get_uniq_id;
}

sub process_download
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
	$opts{'segment-size'} = segment_size();

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);

	my @otherfiles = create_otherfiles(filenames_encoding(), $root_dir);

	{
		$opts{partsize} = $DEFAULT_PARTSIZE;
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding partsize/]);
	}

	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

	empty_dir $root_dir;

	with_newfsm {
		$opts{'max-number-of-files'} = 100_000;
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);

		local $opts{'dry-run'}=undef if dryrun();
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/,
			$opts{'segment-size'} ? ('segment-size') : (), dryrun() ? ('dry-run') : ()]);

		my ($parts, $full) = (0, 0);
		if (dryrun()) {
			check_otherfiles_filenames($out, filename(), \@otherfiles, qr/^Will DOWNLOAD \(if available\) archive [A-Za-z0-9_-]+ \(\s*filename\s+(.*)\)$/, 1);
		} else {
			for (split ("\n", $out)) {
				unless (/otherfile/) {
					if (/Downloaded part of archive/) {
						$parts++
					} elsif (/Downloaded archive/) {
						$full++
					} else {
						# other lines
					}
				}
			}
			if ($opts{'segment-size'} && $opts{'segment-size'}*1024*1024 < filesize()) {
				use POSIX qw/ceil/;
				my $part_count = ceil(filesize()/($opts{'segment-size'}*1024*1024));
				confess unless $parts == $part_count;
				confess if $full;
			} else {
				confess if $parts;
				confess unless $full;
			}
		}
	};

	unless (dryrun()) {
		check_otherfiles(filenames_encoding(), $root_dir, @otherfiles) if @otherfiles && $FASTMODE < 3;
		confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);
	}

	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
}


sub process_retrieve
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

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);

	my @otherfiles = create_otherfiles(filenames_encoding(), $root_dir);

	{
		$opts{partsize} = $DEFAULT_PARTSIZE;
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding partsize/]);
	}


	empty_dir $root_dir;

	with_newfsm {
		$opts{'max-number-of-files'} = 100_000;
		local $opts{'dry-run'}=undef if dryrun();
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/,
			dryrun() ? ('dry-run') : ()]);

		my ($parts, $full) = (0, 0);
		if (dryrun()) {
			check_otherfiles_filenames($out, filename(), \@otherfiles, qr/^Will RETRIEVE archive [A-Za-z0-9_-]+ \(\s*filename\s+(.*)\)$/, 1);
		} else {
			for (split ("\n", $out)) {
				if (/Retrieved Archive/) {
					$parts++
				}
			}
			die unless $parts == @otherfiles + 1;
		}
	};

	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
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

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}])
		unless dryrun();

	my @otherfiles = create_otherfiles(filenames_encoding(), $root_dir);

	{
		local $ENV{NEWFSM}=$ENV{USENEWFSM};
		local $opts{'dry-run'} = undef if dryrun();
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);

		check_otherfiles_filenames($out, filename(), \@otherfiles, qr/^Will UPLOAD (.*)$/) if (dryrun());
	}

	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

	empty_dir $root_dir;
	unless (dryrun()) {
		$opts{'max-number-of-files'} = 100_000;
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/]);

		check_otherfiles(filenames_encoding(), $root_dir, @otherfiles) if @otherfiles && $FASTMODE < 3;
		confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);

		empty_dir $root_dir;
		run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/])
			unless dryrun();
		run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
	}

}

sub process_retrieve_inventory
{
	empty_dir $DIR;

	my %opts;
	set_vault \%opts;
	$opts{dir} = my $root_dir = "$DIR/root";

	mkpath $opts{dir};

	my $content = get_file_body('normal', 1);
	my $filenames_encoding = 'UTF-8';


	my $journal_name = 'journal';
	my $journal_fullname = "$DIR/$journal_name";
	$opts{journal} = $journal_fullname;

	$opts{'terminal-encoding'} = my $terminal_encoding = $filenames_encoding;
	$opts{'filenames-encoding'} = $filenames_encoding;

	$opts{concurrency} = $DEFAULT_CONCURRENCY;

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);

	for (1..before_files()) {
		create_file($filenames_encoding, $root_dir, "before_file_$_", $content);
	}
	with_newfsm {
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
	};

	empty_dir $root_dir;
	$opts{'max-number-of-files'} = 100_000;
	{
		local $opts{filter} = '+before_file* -';
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding filter/]);
		confess unless $out =~ /Retrieved Archive/ || !before_files();
	}


	with_newfsm {
		local $opts{'request-inventory-format'} = first_inventory_format();
		run_ok($terminal_encoding, $^X, $GLACIER, 'retrieve-inventory', \%opts, [qw/request-inventory-format config terminal-encoding vault filenames-encoding/])
			if inventory_count() >= 1;
	};

	my $t0 = [gettimeofday];

	empty_dir $root_dir;

	for (1..after_files()) {
		create_file($filenames_encoding, $root_dir, "after_file_$_", $content);
	}
	with_newfsm {
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
	};

	empty_dir $root_dir;
	$opts{'max-number-of-files'} = 100_000;
	{
		local $opts{filter} = '+after_file* -';
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding filter/]);
		confess unless $out =~ /Retrieved Archive/ || !after_files();
	}

	usleep(10000) while (tv_interval ( $t0, [gettimeofday]) < 1.1); # we need inventory time to differ 1 second

	with_newfsm {
		local $opts{'request-inventory-format'} = second_inventory_format();
		run_ok($terminal_encoding, $^X, $GLACIER, 'retrieve-inventory', \%opts, [qw/request-inventory-format config terminal-encoding vault filenames-encoding/])
			if inventory_count() >= 2;
	};

	my $new_journal = "$journal_fullname.new";
	with_newfsm {
		local $opts{'new-journal'} = $new_journal;
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'download-inventory', \%opts, [qw/config new-journal terminal-encoding vault filenames-encoding/]);
		my $expected_format;
		if (inventory_count() == 2) {
			$expected_format = second_inventory_format();
		} elsif (inventory_count() == 1) {
			$expected_format = first_inventory_format();
		}
		if (inventory_count()) {
			$expected_format = uc $expected_format;
			confess $expected_format unless $out =~ /Downloaded inventory in $expected_format format/;
		}
	};

	my ($is_before, $is_after) = (0, 0);

	if (inventory_count()) {
		open my $f, "<", $new_journal or confess;
		while (<$f>) {
			$is_before++ if /\tbefore_file/;
			$is_after++ if /\tafter_file/;
		}
		close $f;
	} else {
		confess if -s $new_journal; # TODO: -s or -e ?
	}

	if (inventory_count() == 2) {
		confess unless $is_before == before_files();
		confess unless $is_after == after_files();
	} elsif (inventory_count() == 1) {
		confess unless $is_before == before_files();
		confess if $is_after;
	}

	empty_dir $root_dir;
	{
		#local $opts{journal} = $new_journal if inventory_count();
		run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	}
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
	$opts{'new'}=undef if @otherfiles; # TODO: different "otherfiles" mode - "new" or "replace-modified"
	$opts{'replace-modified'}=undef;
	$opts{'detect'} = $detect_option;
	{
		local $ENV{NEWFSM}=$ENV{USENEWFSM};
		local $opts{'dry-run'}= undef if dryrun();
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);

		#

		if (dryrun()) {
			if ($is_upload) {
				if ($is_treehash) {
					check_otherfiles_filenames($out, filename(), [], qr/^Will VERIFY treehash and UPLOAD (.*) if modified/);
				} else {
					check_otherfiles_filenames($out, filename(), \@otherfiles, qr/^Will UPLOAD (.*)$/);
				}
			} else {
				my $filename = filename();
				my $is_ascii = $filename =~ /^[\x01-\x7f]+$/;
				confess if ($is_ascii && $out =~ /Will.*\Q$filename.*\n/);
			}
		} else {
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

	}

	if ($FASTMODE < 10) {
		unless (dryrun()) {
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
	}
	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
}

sub process_sync_missing
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

	$opts{'terminal-encoding'} = my $terminal_encoding = terminal_encoding();
	$opts{'filenames-encoding'} = filenames_encoding();

	$opts{concurrency} = concurrency();

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	with_newfsm {
		run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
	};
	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);
	empty_dir $root_dir;

	my $file_mtime = 123456;

	# creating file
	create_file(filenames_encoding(), $root_dir, filename(), mtime => $file_mtime, $content);
	$opts{partsize} = $DEFAULT_PARTSIZE;
	run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);

	# delete the file
	delete_file(filenames_encoding(), $root_dir, filename()) if is_missing();

	my @otherfiles = create_otherfiles(filenames_encoding(), $root_dir);

	$opts{partsize} = partsize();
	$opts{'new'}=undef if @otherfiles; # TODO: different "otherfiles" mode - "new" or "replace-modified"
	$opts{'delete-removed'}=undef;
	with_newfsm {
		local $opts{'dry-run'}=undef if dryrun();
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);

		if (is_missing()) {
			if (dryrun()) {
				check_otherfiles_filenames($out, filename(), [], qr/Will DELETE archive [A-Za-z0-9_-]+\s*\(\s*filename\s+(.*)\)/, 1);
			} else {
				confess unless ($out =~ /\sDeleted\s/s);
			}
		} else {
			if (dryrun()) {
				confess if ($out =~ /Will DELETE/s);
			} else {
				confess if ($out =~ /\sDeleted\s/s);
			}
		}

	};

	if ($FASTMODE < 10) {
		unless (dryrun()) {
			empty_dir $root_dir;
			$opts{'max-number-of-files'} = 100_000;
			run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);
			run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/]);

			check_otherfiles(filenames_encoding(), $root_dir, @otherfiles) if @otherfiles && $FASTMODE < 3;
			run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding filenames-encoding/])
				if @otherfiles && $FASTMODE < 5;
			if (is_missing()) {
				confess if check_file(filenames_encoding(), $root_dir, filename(), $content);
			} else {
				confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);
			}
		}
	}
	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/]);
	with_newfsm {
		run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
	};
}


sub process_upload_file
{
	empty_dir $DIR;

	my %opts;
	set_vault \%opts;
	my $root_dir = "$DIR/root";


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

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}])
		unless dryrun();

	my $content = get_file_body(filebody(), filesize());
	my $real_filename = do {
		if (upload_file_type() eq 'normal') {
			create_file(filenames_encoding(), $root_dir, filename(), $content);
			"$root_dir/".filename()
		} elsif (upload_file_type() =~ /^(relfilename|stdin)$/) {
			my $dummyfile = "dummyfile";
			create_file(filenames_encoding(), $root_dir, $dummyfile, $content);
			"$root_dir/$dummyfile";
		} else {
			confess;
		}
	};

	with_newfsm sub {
		my $out;
		if (upload_file_type() eq 'normal') {
			local $opts{dir} = $root_dir;
			local $opts{filename} = $real_filename;
			$out = run_ok($terminal_encoding, $^X, $GLACIER, 'upload-file', \%opts);
		} elsif (upload_file_type() eq 'relfilename') {
			local $opts{filename} = $real_filename;
			local $opts{'set-rel-filename'} = filename();
			$out = run_ok($terminal_encoding, $^X, $GLACIER, 'upload-file', \%opts);
		} elsif (upload_file_type() eq 'stdin') {
			local $opts{'stdin'} = undef;
			local $opts{'set-rel-filename'} = filename();
			local $opts{'check-max-file-size'} = 1_000;
			(my $code, $out) = run_with_pipe(sub {
				my ($f) = @_;
				copy($real_filename, $f);
			}, $terminal_encoding, $^X, $GLACIER, 'upload-file', \%opts);
			confess $code if $code;
		} else {
			confess;
		}
	};

	empty_dir $root_dir;

	$opts{'max-number-of-files'} = 100_000;
	$opts{dir} = $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/]);

	confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);

	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault filenames-encoding/])
		unless dryrun();
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);


}


sub process_purge_vault
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
	$opts{'filenames-encoding'} = my $filenames_encoding = filenames_encoding();

	$opts{concurrency} = concurrency();

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);

	my @otherfiles = create_otherfiles(filenames_encoding(), $root_dir);

	create_file($filenames_encoding, $root_dir, "before_file_1", $content) if filtering();

	{
		local $opts{concurrency} = $DEFAULT_CONCURRENCY;
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
	}

	with_newfsm sub {
		local $opts{filter} = '-before_file* +' if filtering();
		local $opts{dir};
		delete $opts{dir};
		local $opts{'dry-run'} = undef if dryrun();
		my $out = run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts);

		if (dryrun()) {
			confess unless $out =~ /Will DELETE archive/;
		} else {
			confess unless $out =~ /Deleted\s/;
		}

	};

	empty_dir $root_dir;
	$opts{'max-number-of-files'} = 100_000;
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files filenames-encoding/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault filenames-encoding/]);
	if (dryrun()) {
		for (@otherfiles) {
			confess unless check_file($filenames_encoding, $root_dir, $_->{dest_filename}||confess, $_->{file_id}||confess);
		}
		confess unless check_file($filenames_encoding, $root_dir, filename(), $content);
		if (filtering()){
			confess unless check_file($filenames_encoding, $root_dir, "before_file_1", $content);
		}
	} else {
		for (@otherfiles) {
			confess if check_file($filenames_encoding, $root_dir, $_->{dest_filename}||confess, $_->{file_id}||confess);
		}
		confess if check_file($filenames_encoding, $root_dir, filename(), $content);
		if (filtering()){
			confess unless check_file($filenames_encoding, $root_dir, "before_file_1", $content);
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
		} elsif (subcommand() eq 'sync_missing') {
			process_sync_missing();
		}
	} elsif (get "command" eq 'retrieve_inventory') {
		process_retrieve_inventory();
	} elsif (get "command" eq 'download') {
		process_download();
	} elsif (get "command" eq 'retrieve') {
		process_retrieve();
	} elsif (get "command" eq 'upload_file') {
		process_upload_file();
	} elsif (get "command" eq 'purge_vault') {
		process_purge_vault();
	} else {
		confess;
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
	my %existing_tasks;
	if (defined $STATE_FILE && -e $STATE_FILE) {
		open my $f, "<:encoding(UTF-8)", $STATE_FILE or confess "cannot open $STATE_FILE $!";
		%existing_tasks = map { $_ => 1 } map { chomp; $_ } <$f>;
		close $f or confess $!;
	}
	my @tasks = grep { !$existing_tasks{$_} } map { chomp; $_ } <STDIN>;
	my $i = 0;
    part { $i++ % $N; } @tasks;
}

empty_dir $BASE_DIR;
mkpath $GLOBAL_DIR;
$SIG{INT} = sub { die "SIGINT!\n";  };
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
		print STDERR "child terminated with $?\n";
		kill 'TERM', $_ for keys %pids;
	} else {
		delete $pids{$p};
	}
}
print STDERR "WARN: PIDs left in list\n" if %pids && $ok;
print STDERR ($ok ? "\n===\n===OK===\n===\n" : "\n===\n===FAIL===\n===\n");
exit($ok ? 0 : 1);

__END__
