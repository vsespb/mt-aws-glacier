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

our $DIR='/dev/shm/mtaws';
our $GLACIER='../../../src/mtglacier';
our $N;

GetOptions ("n=i" => \$N);
$N or confess $N;

$ENV{MTGLACIER_FAKE_HOST}='127.0.0.1:9901';

binmode STDOUT, ":encoding(UTF-8)";
binmode STDIN, ":encoding(UTF-8)";


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
		for (@$task) {
			print "$_\n";
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

__END__
