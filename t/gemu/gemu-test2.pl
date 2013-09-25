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
use VariantEngine;

our $DIR='/dev/shm/mtaws';
our $GLACIER='../../../src/mtglacier';

$ENV{MTGLACIER_FAKE_HOST}='127.0.0.1:9901';

binmode STDOUT, ":encoding(UTF-8)";

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
	open (my $F, ">", $binaryfilename);
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

	$opts{concurrency} = concurrency();
	$opts{partsize} = partsize();

	my $config = "$DIR/glacier.cfg";
	create_config($config, $terminal_encoding);
	$opts{config} = $config;

	run_ok($terminal_encoding, $^X, $GLACIER, 'create-vault', \%opts, [qw/config/], [$opts{vault}]);
	{
		local $ENV{NEWFSM}=1;
		run_ok($terminal_encoding, $^X, $GLACIER, 'sync', \%opts);
	}

	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

	empty_dir $root_dir;

	$opts{'max-number-of-files'} = 100_000;
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore', \%opts, [qw/config dir journal terminal-encoding vault max-number-of-files/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'restore-completed', \%opts, [qw/config dir journal terminal-encoding vault /]);
	#run_ok($terminal_encoding, $^X, $GLACIER, 'check-local-hash', \%opts, [qw/config dir journal terminal-encoding/]);

	confess unless check_file(filenames_encoding(), $root_dir, filename(), $content);

	empty_dir $root_dir;
	run_ok($terminal_encoding, $^X, $GLACIER, 'purge-vault', \%opts, [qw/config journal terminal-encoding vault/]);
	run_ok($terminal_encoding, $^X, $GLACIER, 'delete-vault', \%opts, [qw/config/], [$opts{vault}]);
}


process sub {

	add command => qw/sync/;
	add sub {
		if (get "command" eq 'sync') {
			add subcommand => qw/sync_new/;
			add sub {
				if (subcommand() eq 'sync_new') {
					# filename
					add sub {
						add filename_type => qw/zero default russian/;
						add sub {
							filename => do {
								if (filename_type() eq 'zero') {
									"0"
								} elsif (filename_type() eq 'default') {
									"somefile"
								} elsif (filename_type() eq 'russian') {
									"файл"
								} else {
									confess;
								}
							}
						}
					};
					# encoding of that filename
					add filenames_encoding => qw/UTF-8/;


					# size, partsize and concurrency
					add sub {
						add filesize => (1, 1024*1024-1, 4*1024*1024+1, 100*1024*1024-156897);
						add partsize => qw/1 2 4/;
						add concurrency => qw/1 2 4 20/;
						add sub {
							add sub { get "partsize" == 1 || get("filesize")/(1024*1024) >= get "partsize"; };
							add sub {
								my $r = get("filesize") / (get("partsize")*1024*1024);
								if ($r < 3 && get "concurrency" > 2) {
									return 0;
								} else {
									return 1;
								}
							};
						};
					};

					# encoding stuff
					add sub {
						add sub { russian_text => filename_type() eq 'russian'; };
						add sub { terminal_encoding_type => qw/utf singlebyte/ };
						add sub { get "russian_text" || get "terminal_encoding_type" eq 'utf';};
						add sub {
							if (get "russian_text" && get "terminal_encoding_type" eq 'singlebyte') {
								terminal_encoding => qw/UTF-8 KOI8-R CP1251/;
							} else {
								terminal_encoding => "UTF-8"
							}
						};
					};

					# file content stuff
					add sub {
						add sub { filebody => qw/normal zero/ };
						add sub { filesize() == 1 || filebody() eq 'normal'}; # non-normal filebody only for 1-byte length files
						add sub { filename_type() eq 'default' || filebody() eq 'normal'}; # non-normal filebody only for default filetype
					};
				};
			};
		} else {
			1;
		}
	};


} => sub {
	if (command() eq 'sync') {
		if (subcommand() eq 'sync_new') {
			process_sync_new();
		} elsif (subcommand() eq 'sync-modified') {
			process_sync_modified();
		}
	}
};


__END__

	add command => qw/sync/;
	add sub {
		if (get "command" eq 'sync') {
			add subcommand => qw/sync_new/;
			add sub {
				die;
			};
		} else {
			1;
		}
	};


