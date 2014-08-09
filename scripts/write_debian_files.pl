#!/usr/bin/env perl

use strict;
use warnings;
use Carp;
use File::Copy;
use File::Path;

my $BASEDIR = $ARGV[0]||confess;
our $DISTRO_TYPE = $ARGV[1]||confess;
my $distro = $ARGV[2]||confess;


our $OUTDIR = "$BASEDIR/$distro/debian";
our $COMMONDIR = "$BASEDIR/common_debian";
our $CHANGELOG = "$OUTDIR/changelog";
our $CONTROL= "$OUTDIR/control";

our $PACKAGE = 'libapp-mtaws-perl';
our $CPANDIST = 'App-MtAws';
our $MAINTAINER = 'Victor Efimov <victor@vsespb.ru>';

confess unless $DISTRO_TYPE =~ /^(ubuntu|debian)$/;

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
		next if $_->{re} && $distro !~ $_->{re};
		next if $distro eq 'trusty' && $_->{upstream_version} le '1.111';
		my $version;
		if ($DISTRO_TYPE eq 'ubuntu') {
		    $version = "$_->{upstream_version}-0ubuntu$_->{package_version}~${distro}1~ppa1";
		} elsif ($DISTRO_TYPE eq 'debian') {
			my $v = do {
				if ($distro eq 'jessie') {
					8
				} elsif ($distro eq 'wheezy') {
					7
				} elsif ($distro eq 'squeeze') {
					6
				} else {
					confess "unknown $distro for debian";
				}
			};
		    $version = "$_->{upstream_version}-0vdebian$_->{package_version}~v$v~mt1";
		} else {
		    confess;
		}
		print $f "$PACKAGE ($version) $distro; urgency=low\n\n";
		print $f $_->{text};
		print $f "\n";
		print $f " -- $MAINTAINER  $_->{date}\n\n";
	}
	close $f or confess;
}

sub entry(@)
{
	my ($upstream_version, $package_version, $date, $text, $re) = (shift, shift, shift, shift, pop, shift);
	push @{$_changelog}, {
		upstream_version => $upstream_version,
		package_version => $package_version,
		date => $date,
		re => $re,
		text => $text
	};
}

sub write_control
{
	my ($distro) = @_;

	my @build_deps = qw/libtest-deep-perl libtest-mockmodule-perl libdatetime-perl libmodule-build-perl/;

	my $is_lucid = $distro =~ /(lucid|squeeze)/i;

	push @build_deps, 'libtest-spec-perl', 'libhttp-daemon-perl' unless $is_lucid;

	my @deps = qw/libwww-perl libjson-xs-perl/;
	my @recommends = $is_lucid ?  () : qw/liblwp-protocol-https-perl/;
	my $build_deps = join(", ", @deps, @build_deps);
	my $deps = join(", ", @deps);
	my $recommends= join(", ", @recommends);
	my $recommends_line = @recommends ? "Recommends: $recommends\n" : "";
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
${recommends_line}Description: mt-aws/glacier - Perl Multithreaded Multipart sync to Amazon Glacier
 Amazon Glacier is an archive/backup service with very low storage price.
 However with some caveats in usage and archive retrieval prices.
 mt-aws-glacier is a client application for Amazon Glacier, written
 in Perl programming language, for *nix systems.
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
	entry '1.120', 1, 'Sat, 09 Aug 2014 23:40:00 +0400', <<'END';
  * list-vaults command implemented
END

	entry '1.117', 1, 'Tue, 29 Jul 2014 11:40:00 +0400', <<'END';
  * Fixed - previous version introduced a check that Mozilla::CA module presents. This could be a bug on some systems
  (i.e. Debian). Debian decoupled LWP::Protocol::https from Mozilla::CA but patched LWP::Protocol::https so it use system
  CA store. Thus version v1.116 crashed with error message when trying to use HTTPS (only Debian systems affected where
  mtglacier installed without CPAN). Now reverting the check on configuration stage and leave only check when we are
  really getting error that SSL is broken. So it will advice to install Mozilla::CA only on systems where HTTPS indeed
  broken.

  * Dropping Ubuntu Saucy and Quantal PPA build, as it's EOL and Ubuntu PPA refuses to build packages.
END

	entry '1.116', 1, 'Sun, 27 Jul 2014 23:16:00 +0400', <<'END';
  * Fixed - there can be issue on MacOSX that HTTPS is not working: All requests end up with errors "HTTP connection
  problem (timeout?)". Found that Apple ships LWP::Protocol::https without Mozilla::CA module (and they have no rights to
  do so). So now a README install instructions updated and runtime error thrown if Mozilla::CA is missing and yo're trying
  to use HTTPS. More technical info: http://blogs.perl.org/users/vsespb/2014/07/broken-lwp-in-the-wild.html
  https://github.com/vsespb/mt-aws-glacier/issues/87

  * Fixed - typo in error message.
END

	entry '1.115', 1, 'Mon, 26 May 2014 00:43:00 +0400', <<'END';
  * Fixed - crash/error when uploading large files with partsize=1024, when "old" Digest::SHA (< 5.63; shipped with most
  of current linux distros) is installed. Old Digest::SHA has a bug, there was a workaround for it (i.e. message asking
  to upgrade module) when it's used with large files on 32bit machines, but apparently seems 64bit machines
  also affected.
  Now a message removed, instead workaround code written so it now works with old buggy versions fine (i.e. splits large
  chunks into smalled ones when feeding Digest::SHA).

  * Since v1.113 Ubuntu Raring 13.04 PPA is discontinued (due to End of Life of Ubuntu Raring, launchpad PPA stopped
  building binaries for it)
END

	entry '1.114', 1, 'Thu, 20 Feb 2014 16:46:00 +0400', <<'END';
  * Fixed: a crash with message:
  UNEXPECTED ERROR: archive XXXXXX...XXX not found in archive_h

  mtglacier was crashing if --filter/--include/--exclude options applied, and a file, previously deleted in
  Journal (i.e. with --purge-vault or --delete-removed) excluded by this filter.

  i.e. when file deleted, a record about deletion is appended to Journal (and previously there was a record
  about creation). when journal is read, creation record is skipped (because filters applied), but deletion record was
  not checked by filter. thus mtglacier detected it problem with journal consistency (attempt to delete unexistant file)
END
	entry '1.113', 2, 'Sat, 1 Feb 2014 18:10:00 +0400', <<'END';
  * Rebuild for Ubuntu - remove some extra files from tarrball.
END

	entry '1.113', 1, 'Sat, 1 Feb 2014 17:50:00 +0400', <<'END';
  * Fixed: Y2038 problem with file modification time in metadata (i.e. journal and Amazon Glacier servers).
  Some OSes and filesystems don't support years after 2038 (i.e. Linux 32bit)
  Some perl versions don't support handling dates after 2038 (i.e. 32bit perl before 5.12 and
  64bit perl 5.8.8 (RHEL5), 5.10.0 (some SUSE))

  There is not much sense in having files with file modification after Y2038 or before Y1902, however such file can
  appear in filesystems due to bugs in other software etc.

  Fixing now inconsistency in behaviour with such metadata between different OS/perl versions.

  After this fix file modification time will be restored correctly from Amazon servers to journal (via download-inventory)
  on all platforms, for all years in range 1000-9999.

  However if your OS/filesystem does not work with such dates, anything except correct date in journal file
  is not guaranteed.

  Before this fix, such dates could result in lost of filenames and modification time in journal (filename replaced
  with random token) when restoring inventory (you are affected if you uploaded file on 64bit system with date
  after Y2038, but then restored on 32bit system).

  * Documentation: Also, note about Y2038 added to "Limitationss" section.

  * CSV inventory parsing - making it 30% slower, but more consistent with what Amazon documented about its format
  https://forums.aws.amazon.com/thread.jspa?threadID=141807&tstart=0

  * Cosmetic changes to docs

  * CPAN install - on some systems like ARM, some NAS, 32bit OSes decrease number of concurrent tests during install.
  Might help preventing out-of-memory problems (but makes test slower).
END

	entry '1.112', 1, 'Tue, 14 Jan 2014 01:34:00 +0400', <<'END';
  * PPA package for Ubuntu 14.04 added to Ubuntu PPA (+ fixes in metadata of Debian/Ubuntu packages)

  * Workaround: 31 December 2013 Amazon introduced extension to inventory retrieval API: now one can request for just
  a part of inventory. This, however, can break mt-aws-glacier behaviour in rare circumstances i.e. when you use 3rd
  party app to request a part of inventory and then run mt-aws-glacier to get full inventory, mt-aws-glacier can
  download partial inventory instead of full. (details here https://forums.aws.amazon.com/thread.jspa?threadID=143107).

  Releasing workaround now - mt-aws-glacier now tried to check if this is a full inventory (it's still possible for the
  bug to appear very-very rare circumstances i.e. if 3rd party app will request for part inventory with limit set and
  then request for continuation without any limits).

  Also, now all inventory jobs raised by mt-aws-glacier have special marker. In the future versions bug will be fully
  fixed as all non-mtglacier jobs will be disabled.

  * Fixed several brittle tests introduced in v1.110, preventing mtglacier from install via CPAN on some systems:
  - systems with perl 5.18.1, 5.18.2 and stock version of Digest::SHA
  - old systems (i suspect RHEL5 without any CPAN modules installed) with old version of File::Temp
  - Cygwin

  * Documentation: Warning about incompatibility of metadata added to Must Read section

  * Documentation: Fixed - installation instructions for Debian via custom repository improved - lsb_release command,
  used in install instruction, was not a part of (some?) minimal Debian installs. So some users experienced problems
  installing mtglacier first time. I suspect users who use FISH shell were affected too.
END

	entry '1.111', 1, 'Fri, 20 Dec 2013 22:35:00 +0400', <<'END';
  * Brittle test fixed (i386, old Digest::SHA)
END

	entry '1.110', 1, 'Fri, 20 Dec 2013 22:10:00 +0400', <<'END';
  * Compatibility: upload-file with --filename option behaviour slightly changed:
  both --filename and --dir now resolved to full paths, before determining relative path from --dir` to --filename`
  So f you have `/dir/ds` symlink to `/dir/d3` directory, then `--dir=/dir` `--filename=/dir/ds/file` will result in
  relative filename `d3/file` not `ds/file`. Previously you would get d3/file. Also now all parent directories has
  to be readable.

  * Documentation: documentation for upload-file updated.

  * Fixed: #63 internaly mtglacier was using absolute filenames when reading/writing file in filesystem, even if user
  specified relative. Seems that was wrong. Undex Unix file can be readable by relative name but unaccessible by real,
  absolute name if path components of this name are unreadable. Fixed now - always use relative filenames in all commands
  except upload-file command (where it's documented that absolute names are used).
  This change does not affect relative filenames stroed in journal or amazon glacier metadata in any way.
  This change might affect filenames format that you see in mtglacier output.

  * Fixed: some bugs related to directory traversal under old-old perl installations (RHEL 5.x, when no new
  CPAN modules installed) worked around.

  * Fixed: upload-file with --filename and --dir were not working correctly for most of perl installations
  if dir started with "..". This due to bug https://rt.perl.org/Public/Bug/Display.html?id=111510 in File::Spec module.
  Currently upload-file behaviour changed (see above in ChangeLog) so  mtglacier not affected. In previous versions this
  would result in wrong relative filenames in journal and Amazon glacier metadata
  (precisely, those filenames are without path prefix, as if they would be in current directory, otherwise filename
  part is correct).

  * Workaround: Digest::SHA perl module prior to version 5.62 calculates SHA256 wrong on 32bit machines, when data
  size is more than 2^29 bytes. Now mtglacier throws an error if --partsize >= 512Mb and machine is 32bit and digest-sha
  version is below 5.62. Commands which don't use --partsize are unaffected.

  * Fixed: Amazon CSV format parsing: Amazon escapes doublequote with backslash but.. does not escape backslash itself.
  https://forums.aws.amazon.com/thread.jspa?threadID=141807
  This format is undocumented and broken by design. Fixing parser now to parse this.
  this bug was not affecting any real use of mtglacier as mtglacier does not use backslashes in metadata and ignores
  foreign metadata.

  * Cosmetic changes to process manager code
END

	entry '1.103', 1, 'Sat, 14 Dec 2013 15:10:00 +0400', <<'END';
  * Fixed: issue #48 download-inventory was crashing if there was a request for inventory retrieval in CSV format
  issued by 3rd party application. mt-aws-glacier was not supporting CSV and thus crashing.
  It's hard to determine inventory format until you download it, so mt-aws-glacier now supports CSV parsing.

  * Fixed: download-inventory command now fetches latest inventory, not oldest

  * Added --request-inventory-format option for retrieve-inventory commands

  * Documentation: updated docs for retrieve-inventory and retrieve-inventory and download-inventory commands
END

	entry '1.102', 1, 'Tue, 10 Dec 2013 19:38:00 +0400', <<'END';
  * Fixed: memory/reasource leak, introduced in v1.100. Usually resulting in crash after uploading ~ 1000 files ( too
  many open files error)

  * Minor improvements to process termination code
END

	entry '1.101', 1, 'Sun, 8 Dec 2013 12:50:00 +0400', <<'END';
  * Fixed: CPAN install was failing for non-English locales due to brittle test related to new FSM introduced in 1.100
  Also error message when reading from file failed in the middle of transfer was wrong for non-English locales.

  * Added validation - max allowed by Amazon --partsize is 4096 Mb

  * Fixed: --check-max-file-size option validation upper limit was wrong. Was: 40 000 000 Mb; Fixed: 4 096 0000 Mb
END

	entry '1.100', 1, 'Sat, 7 Dec 2013 15:30:00 +0400', <<'END';
  * Nothing new for end users (I hope so ). Huge internal refactoring of FSM (task queue engine) + unit
  tests for all new FSM + integration testing for all mtglacier commands.
END
	entry '1.059', 1, 'Sat, 30 Nov 2013 13:54:00 +0400', <<"END";
  * Fixed: Dry-run with restore completed was crashing.
  Fixed a bug introduced in v0.971
  dry-run and restore-completed used archive_id instead of relative filename and thus was crashing with message:
  UNEXPECTED ERROR: SOMEARCHIVEID not found in journal at ... /lib/App/MtAws/Journal.pm line 247.
END

	entry '1.058', 1, 'Fri, 8 Nov 2013 21:50:00 +0400', << "END";
  * Fixed - when downloading inventory there could be Perl warning message ("use initialized ..") in case when some
  specific metadata (x-amz-archive-description) strings (like empty strings) met. Such metadata can appear if
  archives were uploaded by 3rd party apps.

  * Fixed possible deadlock before process termination (after success run or after Ctrl-C), related to issue
  https://rt.perl.org/Ticket/Display.html?id=93428 - select() is not always interruptable. Issue seen
  under heavy load, under perl 5.14, with concurrency=1 (unlikely affects concurrency modes > 1 )

  * Fixed - when deprecated option for command (say, --vault for check-local-hash) was found in config, there was a
  warning that option deprecated, however that should not happen, because everything that is in config should be
  read only when such option required (you should be able to put any unneeded option into config)
END

	entry '1.056', 2, 'Thu, 17 Oct 2013 16:40:30 +0400', << "END";
  * Initial release for Debian 7
END

	entry '1.056', 1, 'Tue, 15 Oct 2013 16:20:30 +0400', << "END";
  * Initial release for launchpad PPA
END

};

write_control $distro;

copy_files $distro;
copy_files_to_debian $distro;
