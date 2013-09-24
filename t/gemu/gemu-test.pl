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
use File::Path qw/mkpath rmtree/;
use App::MtAws::TreeHash;


our ($DIR, $ROOT, $VAULT, $JOURNAL, $NEWJOURNAL, $CFG, $GLACIER, $CONC);
$DIR='/dev/shm/mtaws';
$VAULT="test1";
$GLACIER='../../../src/mtglacier';

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
			print $f "A\t456\tCREATED\t$archive_id\t$testfile->{filesize}\t123\t$treehash\t$testfile->{relfilename}\n";
		}
	}
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



sub process_one
{
	my ($data) = @_;
	rmtree $DIR;


	my $filenames_encoding = 'UTF-8';

	my %opts;
	$opts{vault} = "test".(++$increment);
	my $root_dir = "$DIR/root";

	$opts{dir} = $root_dir;

	my @create_files = (do {
		if ($data->{filename} eq 'zero') {
			'0';
		} elsif ($data->{filename} eq 'russian') {
			"файл"
		} else {
			'somefile';
		}
	});

	my $filebody = $data->{filebody} or confess;
	my $filesize = $data->{filesize};

	confess if $filebody eq 'zero' && $filesize != 1;

	my $files = [map {
		{ relfilename => $_, filesize => $filesize, content => $filebody eq 'zero' ? '0' : 'x'x$filesize }
	} @create_files];
	create_files($filenames_encoding, $root_dir, $files);

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
	$opts{journal} = $journal_fullname;


	my $will_upload = $data->{willupload};
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
	} elsif ($data->{sync_mode} eq 'sync-modified') {
		$opts{'replace-modified'}=undef;
	} elsif ($data->{sync_mode} eq 'sync-deleted') {
		$opts{'delete-removed'}=undef;
	} else {
		confess $data->{sync_mode};
	}
	$opts{filter} = \@filter;


	$opts{'terminal-encoding'} = my $terminal_encoding = $data->{terminal_encoding};

	$opts{concurrency} = $data->{concurrency} or confess Dumper $data;
	$opts{partsize} = $data->{partsize} or confess;


	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	my @opts = map { my $k = $_; ref $opts{$k} ? (map { $k => $_ } @{$opts{$_}}) : ( $k => $opts{$k} )} keys %opts;
	my @opts_e = map { encode($terminal_encoding, $_, Encode::DIE_ON_ERR|Encode::LEAVE_SRC) } @opts;
	#$terminal_encoding, $perl, $glacier, $command, $opts, $optlist, $args

	#print "============================W $will_upload\n";
	if ($will_upload) {
		run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
		{
			local $ENV{NEWFSM}=1;
			run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
		}
		run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

		rmtree $root_dir;
		mkpath $root_dir;

		#run_fail($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);
		$opts{'max-number-of-files'} = 100_000;
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files/]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault /]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);
		rmtree $root_dir;
		mkpath $root_dir;
		run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault/]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
	} else {
		#print Dumper $data;
		run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
		{
			local $ENV{NEWFSM}=1;
			run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
		}
		rmtree $root_dir;
		run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
	}
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

		if (@vals) {
			for (@vals) {
				process_recursive({%$data, $type => $_}, @variants);
			}
		} else {
			if ($type) {
				process_recursive({%$data}, @variants);
			} else {
				return;
			}
		}
	} else {
		print join(" ", map { "$_=$data->{$_}" } sort keys %$data), "\n";
		process_one($data) unless $ENV{GEMU_TEST_LISTONLY};
	}
}

sub process
{
	process_recursive({}, @variants);
}

add(sub { journal_name => qw/default russian/ });
add(sub { filename => qw/zero default russian/ });#latin1
add(sub { match_filter => qw/default match nomatch/ });#
add(sub { journal_match => qw/nomatch match/ });#

add(sub {
	if (get("journal_match") eq "match" or get("match_filter") eq "nomatch") {
		willupload => 0
	} else {
		willupload => 1
	}
});

add(sub {
	if (get("willupload") == 0 or get("match_filter") ne "default") {
		filterstest => 1
	} else {
		filterstest => 0
	}
});


add(sub { filesize => (1, 1024*1024-1, 4*1024*1024+1, 100*1024*1024-156897) });#0

add sub { return get "filename" ne 'default' || get "filesize" == 1 };

add(sub {
	return !get "filterstest" || get "filesize" == 1;
});#0

add(sub { filebody => qw/normal zero/ });
add sub { get "filesize" == 1 || get "filebody" eq 'normal'};
#add sub { print "#", get "filebody", "\n"};
add(sub { otherfiles => qw/none/ });# many huge
add(sub { sync_mode => qw/sync-new/ });# sync-modified sync-deleted

add(sub { partsize => qw/1 2 4/ });
add(sub {
	return get "partsize" == 1 || get("filesize")/(1024*1024) >= get "partsize";
});


add(sub { concurrency => qw/1 2 4 20/ });#match nomatch
add(sub {
	#print "#", get("filesize"), "\t", get("partsize"), "\n";
	my $r = get("filesize") / (get("partsize")*1024*1024);
	if ($r < 3 && get "concurrency" > 2) {
		return 0;
	} else {
		return 1;
	}
});

add(sub {
	return !get "filterstest" || (get "concurrency" == 1 && get "partsize" == 1);
});

add sub {
	russian_text => get("filename") eq 'russian' || get("journal_name") eq 'russian';
};

add sub { terminal_encoding_type => qw/utf singlebyte/ };
add sub {
	return get "russian_text" || get "terminal_encoding_type" eq 'utf';
};

add sub {
	if (get "russian_text" && get "terminal_encoding_type" eq 'singlebyte') {
		terminal_encoding => qw/UTF-8 KOI8-R CP1251/;
	} else {
		terminal_encoding => "UTF-8"
	}
};


process();
