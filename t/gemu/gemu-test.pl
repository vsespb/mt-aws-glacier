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

binmode STDOUT, ":encoding(UTF-8)";


my @variants;

sub get($) { die "Unimplemented"; };
sub before($) { die "Unimplemented"; };

sub _add
{
	my $variants = shift;
	if (@_ == 1 ) {
		push @$variants, shift;
	} else {
		my @a = @_;
		push @$variants, sub { @a };
	}
}

sub add
{
	_add(\@variants, @_);
}

sub get_uniq_id()
{
	$$."_".(++$increment);
}

sub gen_archive_id
{
	sprintf("%s%08d", "x" x 130, get_uniq_id);
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
		binmode $F;
		print $F $testfile->{content};
		close $F;
	}
}

sub check_files
{
	my ($filenames_encoding, $root, $files) = @_;
	for my $testfile (@$files) {
		$testfile->{filename} = my $fullname = "$root/$testfile->{relfilename}";
		$testfile->{binaryfilename} = my $binaryfilename = encode($filenames_encoding, $testfile->{filename}, Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
		open (my $F, "<", $binaryfilename) or return 0;
		binmode $F;
		read $F, my $buf, -s $F;
		return 0 if $buf ne $testfile->{content};
	}
	return 1;
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


	my $file = 	{ relfilename => filename_str(), filesize => filesize(), content => get_file_body(filebody(), filesize()) };
	create_files(filenames_encoding(), $root_dir, [$file]);

	my $journal_name = journal_name();
	my $journal_fullname = "$DIR/$journal_name";
	$opts{journal} = $journal_fullname;


	my $will_upload = get "willupload";
	$file->{already_in_journal} = 1 if (journal_match() eq 'match');
	create_journal($journal_fullname, [$file]);

	$opts{filter} = [get_filter(match_filter_type(), $file->{relfilename})];

	$opts{'terminal-encoding'} = my $terminal_encoding = get "terminal_encoding";

	$opts{concurrency} = get "concurrency";
	$opts{partsize} = get "partsize";

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	if ($will_upload) {
		run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
		{
			local $ENV{NEWFSM}=1;
			run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
		}
		run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

		empty_dir $root_dir;

		$opts{'max-number-of-files'} = 100_000;
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files/]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault /]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);
		empty_dir $root_dir;
		run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault/]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
	} else {
		run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
		{
			local $ENV{NEWFSM}=1;
			run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
		}
		rmtree $root_dir;
		run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
	}
}

sub process_sync_modified
{
	empty_dir $DIR;

	my %opts;
	$opts{vault} = "test".get_uniq_id;
	$opts{dir} = my $root_dir = "$DIR/root";


	my $first_file = { relfilename => filename_str(), filesize => filesize(), content => get_first_file_body(filebody(), filesize()) };
	my $file = 	{ relfilename => filename_str(), filesize => filesize(), content => get_file_body(filebody(), filesize()) };
	create_files(filenames_encoding(), $root_dir, [$first_file]);

	my $journal_name = journal_name();
	my $journal_fullname = "$DIR/$journal_name";
	$opts{journal} = $journal_fullname;


	my $will_upload = get "willupload";
	$file->{already_in_journal} = 1 if (journal_match() eq 'match');


	$opts{filter} = [get_filter(match_filter_type(), $file->{relfilename})];

	$opts{'terminal-encoding'} = my $terminal_encoding = get "terminal_encoding";

	$opts{concurrency} = get "concurrency";
	$opts{partsize} = get "partsize";

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	if ($will_upload) {
		run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
		create_journal($journal_fullname, [$first_file]);
		{
			local $ENV{NEWFSM}=1;
			run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
		}
		run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

		empty_dir $root_dir;
		create_files(filenames_encoding(), $root_dir, [$file]);

		$opts{'replace-modified'}=undef;
		$opts{'detect'}='treehash';
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
		empty_dir $root_dir;
		$opts{'max-number-of-files'} = 100_000;
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files/]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault /]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);
		confess if check_files(filenames_encoding(), $root_dir, [$first_file]);
		confess unless check_files(filenames_encoding(), $root_dir, [$file]);
		empty_dir $root_dir;
		run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault/]);
		run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
	} else {
		run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
		{
			local $ENV{NEWFSM}=1;
			run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
		}
		rmtree $root_dir;
		run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
	}
}

sub process_one
{
	if (command() eq 'sync') {
		if (subcommand() eq 'sync-new') {
			process_sync_new();
		} elsif (subcommand() eq 'sync-modified') {
			process_sync_modified();
		}
	}
}

sub process_recursive
{
	my ($data, @variants) = @_;
	no warnings 'redefine';
	local *get = sub($) {
		$data->{+shift} // confess Dumper $data;
	};
	local *before = sub($) {
		confess "use before $_[0]" if defined $data->{$_[0]};
	};
	local *AUTOLOAD = sub {
		use vars qw/$AUTOLOAD/;
		$AUTOLOAD =~ s/^.*:://;
		get("$AUTOLOAD");
	};
	if (@variants) {
		my $v = shift @variants;

		my @additional;
		local *add = sub {
			_add(\@additional, @_);
		};

		my ($type, @vals) = $v->($data);

		if (@additional) {
			process_recursive({%$data}, @additional, @variants);
		} else {
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


add journal_name_type => qw/default russian/;
add sub {
	if (journal_name_type() eq 'default') {
		journal_name => "journal"
	} elsif (journal_name_type() eq 'russian') {
		journal_name => "журнал";
	} else {
		confess "no journal name";
	}
};
add filename => qw/zero default russian/;#latin1
add sub { filename_str => do {
	if (filename() eq 'zero') {
		"0"
	} elsif (filename() eq 'default') {
		"somefile"
	} elsif (filename() eq 'russian') {
		"файл"
	} else {
		confess;
	}
}};
add filenames_encoding => qw/UTF-8/;

add match_filter_type => qw/default match nomatch/;#
add journal_match => qw/nomatch match/;#

add(sub {
	willupload => !(get("journal_match") eq "match" or get("match_filter_type") eq "nomatch");
});

add(sub {
	filterstest =>  get("willupload") == 0 || get("match_filter_type") ne "default";
});


add command => qw/sync/;
add sub {
	if (command() eq 'sync') {
		add subcommand => qw/sync-modified/;# sync-new sync-deleted
		add sub {
			add filesize => (1, 1024*1024-1, 4*1024*1024+1, 100*1024*1024-156897);#0
			add sub { return get "filename" ne 'default' || get "filesize" == 1 };

			add(sub {
				return !get "filterstest" || get "filesize" == 1;
			});#0

			add(sub { filebody => qw/normal zero/ });
			add sub { get "filesize" == 1 || get "filebody" eq 'normal'};
			#add sub { print "#", get "filebody", "\n"};
			add(sub { otherfiles => qw/none/ });# many huge

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
				russian_text => get("filename") eq 'russian' || get("journal_name_type") eq 'russian';
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
			if (subcommand() eq 'sync-new') {

			} elsif (subcommand() eq 'sync-modified') {
				add detect => qw/treehash mtime mtime-and-treehash mtime-or-treehash always-positive size-only/;
				add detect_result => qw/modified notmodified/;
			} else {
				return 0;
			}
		};
	}
};



process();
__END__
	if (get "sync_mode" eq 'sync-new') {
	} elsif (get "sync_mode" eq 'sync-modified') {
		$opts{'replace-modified'}=undef;
	} elsif (get "sync_mode" eq 'sync-deleted') {
		$opts{'delete-removed'}=undef;
	} else {
		confess get "sync_mode";
	}
