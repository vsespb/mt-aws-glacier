#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use File::Copy;
use File::Path;

my $distro = $ARGV[1]||confess;
my $BASEDIR = $ARGV[0]||confess;
our $OUTDIR = "$BASEDIR/$distro/debian";
our $COMMONDIR = "$BASEDIR/common";
our $CHANGELOG = "$OUTDIR/changelog";
our $CONTROL= "$OUTDIR/control";

our $PACKAGE = 'libapp-mtaws-perl';
our $CPANDIST = 'App-MtAws';
our $MAINTAINER = 'Victor Efimov <victor@vsespb.ru>';


mkpath $OUTDIR;
mkpath "$OUTDIR/source";

our $_changelog;

sub write_changelog($&)
{
	my ($distro, $cb) = @_;
	local $_changelog = [];
	$cb->();
	open my $f, ">", $CHANGELOG or confess;
	for (@{$_changelog}) {
		print $f "$PACKAGE ($_->{upstream_version}-$_->{debian_version}ubuntu$_->{ubuntu_version}~${distro}1~ppa1) $distro; urgency=low\n\n";
		print $f $_->{text};
		print $f "\n";
		print $f " -- $MAINTAINER  $_->{date}\n\n";
	}
	close $f or confess;
}

sub entry($$$$$)
{
	my ($upstream_version, $debian_version, $ubuntu_version, $date, $text) = @_;
	push @{$_changelog}, {
		upstream_version => $upstream_version,
		debian_version => $debian_version,
		ubuntu_version => $ubuntu_version,
		date => $date,
		text => $text
	};
}

sub write_control
{
	my ($distro) = @_;
	
	my @build_deps = qw/libtest-deep-perl libtest-mockmodule-perl libtest-spec-perl libhttp-daemon-perl libdatetime-perl libmodule-build-perl/;
	my @deps = qw/libwww-perl libjson-xs-perl/;
	my @recommends = qw/liblwp-protocol-https-perl/;
	my $build_deps = join(", ", @deps, @build_deps);
	my $deps = join(", ", @deps);
	my $recommends= join(", ", @recommends);
	
	open my $f, ">", $CONTROL or confess;
	
	print $f <<"END";
Source: $PACKAGE
Section: perl
Priority: optional
Maintainer: $MAINTAINER
Build-Depends: debhelper (>= 8), perl, $build_deps
Standards-Version: 3.9.2
Homepage: http://search.cpan.org/dist/$CPANDIST/

Package: $PACKAGE
Architecture: all
Depends: \${misc:Depends}, \${perl:Depends}, perl, $deps
Recommends: $recommends
Description: mt-aws/glacier - Perl Multithreaded Multipart sync to Amazon Glacier
END

	close $f or confess
}

sub copy_files
{
	my ($distro) = @_;
	for (qw!compat copyright libapp-mtaws-perl.docs watch rules source/format!) {
		system("cp", "$COMMONDIR/$_", "$OUTDIR/$_") and confess "copy $COMMONDIR/$_ $OUTDIR/$_ $!";
	}
}

sub copy_files_to_debian
{
	my ($distro) = @_;
	for (qw!changelog control compat copyright libapp-mtaws-perl.docs watch rules source/format!) {
		system("cp", "$OUTDIR/$_", "./debian/$_") and confess "copy $OUTDIR/$_, ./debian/$_ $!";
	}
}

write_changelog $distro, sub {
	entry '1.055', 0, 6, 'Thu, 15 Oct 2013 13:20:30 +0400', << "END";
  * Polishing debian package files
END

	entry '1.055', 0, 5, 'Thu, 15 Oct 2013 13:20:30 +0400', << "END";
  * Polishing build dependencies and fix package name
END

	entry '1.055', 0, 4, 'Thu, 14 Oct 2013 20:08:30 +0400', << "END";
  * Fix build dependencies
END

	entry '1.055', 0, 3, 'Thu, 14 Oct 2013 20:08:30 +0400', << "END";
  * Fix build dependencies
END

	entry '1.055', 0, 2, 'Thu, 10 Oct 2013 21:55:30 +0400', << "END";
  * Initial Release.
END

};

write_control $distro;

copy_files $distro;
copy_files_to_debian $distro;
