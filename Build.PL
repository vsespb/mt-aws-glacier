# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

# APP-MTAWS-ROOT-DIR (marker for scripts to check root dir)

use 5.008008; # minumum perl version is 5.8.8, ancient cpan clients will ignore 'requires/perl' below
use strict;
use warnings;
use Module::Build;

use lib qw(lib);


die "OS unsupported\n" if ($^O eq 'MSWin32');

our $MB_VERSION = '0.36';

#https://github.com/Perl-Toolchain-Gang/Module-Build/issues/40
our $MB_BROKEN_RECOMMENDS = ($Module::Build::VERSION >= 0.42) && ($Module::Build::VERSION < 0.4203);

my $build = Module::Build->new(
	module_name => 'App::MtAws',
	author => 'Victor Efimov <vs@vs-dev.com>',
	dist_author => 'Victor Efimov <vs@vs-dev.com>',
	dynamic_config => 1,
	recursive_test_files=>1,
	dist_abstract=>'mt-aws/glacier - Perl Multithreaded Multipart sync to Amazon Glacier',
	license     =>'gpl3',

	# this is a special version of 'mtglacier' script with different shebang and without FindBin
	# http://blogs.perl.org/users/randy_stauner/2011/09/shebangs-with-perlbrew-aliases-and-eumm-and-without-locallib.html
	script_files => ['bin/mtglacier'], # script_files directive since M::B 0.18

	meta_merge => {
		resources => {
			repository => 'https://github.com/vsespb/mt-aws-glacier',
			bugtracker => 'https://github.com/vsespb/mt-aws-glacier/issues',
			homepage => 'http://mt-aws.com/'
		},
	},
	requires => {
		'perl' => 5.008008, # 5.8.8

		'LWP' => '5.803', # ancient CentOS 5.x version
		'HTTP::Request' => 0, # either shipped with LWP, or prereq by LWP, does not contain correct version, sometimes
		'JSON::XS' => '1',


		# core modules for Perl > 5.8.x
		'Digest::SHA' => 0,

		#
		# CORE MODULES OR DUAL-LIFE MODULES
		#
		'Carp' => 0,
		'Encode' => 0,
		'Exporter' => 0,
		'File::Basename' => 0,
		'File::Find' => 0,
		'File::Path' => 0,


		 # for EXLOCK need 0.19
		 # for compatibility with forking 0.19
		 # perl 5.8.8 ships 0.16, 5.8.9 ships 0.20, but 5.9.0 ships 0.14
		 # use 0.16 as we have workarounds for above problems
		'File::Temp' => '0.16',

		'File::Spec' => 0,
		'File::stat' => 0,
		'Getopt::Long' => '2.24',


		# distribution 'IO' v 1.22 released with perl 5.8.8, however it does contains IO::{Hnadle|Pipe|Select} versions lower than 1.22
		'IO::Handle' => 0,
		'IO::Pipe' => 0,
		'IO::Select' => 0,

		'List::Util' => '1.11', # needed for Test::Spec, however 1.19 is released with perl 5.8.9 and 1.13 with perl 5.9
		'POSIX' => 0,
		'PerlIO::encoding' => 0,
		'I18N::Langinfo' => 0,
		'Time::Local' => 0,
		'Time::localtime' => 0,
		'bytes' => 0,
		'constant' => 0,
		'lib' => 0,
		'strict' => 0,
		'integer' => 0,
		'utf8' => 0,
		'warnings' => 0,
		'FindBin' => 0,
		#
		# / CORE MODULES OR DUAL-LIFE MODULES
		#
	},
	build_requires => {
		$ENV{MT_NO_HARNESS} ? () : ('TAP::Harness' => 0),

		# Test::Deep
		# Does not work with 0.090, 0.091 (due to bug in Test::Deep)
		# issue fixed here fixed https://metacpan.org/diff/release/FDALY/Test-Deep-0.091/FDALY/Test-Deep-0.092
		#
		# However I cannot specify version as '!= 0.090, != 0.091' because some CPAN testers (yet) failed to recognize it
		# http://www.cpantesters.org/cpan/report/75a8f356-e307-11e2-bb8b-c8f40b763136
		# http://www.cpantesters.org/cpan/report/de15b36c-e301-11e2-86e0-d3fada4a5016
		# http://www.cpantesters.org/cpan/report/fc48c53e-e2fe-11e2-9ee6-a6098e6b5bd1
		#
		# so, specifying as '0.092'

		'Test::Deep' => '0.092',

		# Test::Simple, Test::More, Test::Builder are part of Test-Simple disto, minimum version 0.88 required as it used by Test::Spec
		# (and Test::Spec failed to declare minimim version)
		'Test::Simple' => '0.88',
		'Test::More' => '0.88',

		'Test::MockModule' => 0,
		'DateTime' => 0,
		'Test::Spec' => 0,
		'URI' => '1.10', # even ancient LWP versions require at least 1.10, so we use it too
		'HTTP::Daemon' => '1.36',
		$ENV{MT_DEB_BUILD} ? () : ('Test::Tabs' => '0.003'),

		# CORE MODULES OR DUAL-LIFE MODULES
		'B' => 0, # test that some scalar IV only to save memory
		'Data::Dumper' => 0,
		'Time::HiRes' => 0,
		'open' => 0,
		'Scalar::Util' => '1.11',

		# Specify Module::Build twice
		'Module::Build' => $MB_VERSION,
	},
	configure_requires => {
		'Module::Build' => $MB_VERSION,
	},
	$MB_BROKEN_RECOMMENDS ? () :
	(
		recommends => {
			'LWP::Protocol::https' => 6,
		}
	),
	$ENV{MT_NO_HARNESS} ?
		() :
		(use_tap_harness    => 1, tap_harness_args   => {
			jobs => ($^O eq 'openbsd' ? 2 : 8) # openBSD has low default ulimits
		}),
);

$build->create_build_script();
__END__
