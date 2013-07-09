
use 5.008008; # minumum perl version is 5.8.8, ancient cpan clients will ignore 'requires/perl' below
use strict;
use warnings;
use Module::Build;

use lib qw(lib);


die "OS unsupported\n" if ($^O eq 'MSWin32' or $^O eq 'cygwin');

my $build = Module::Build->new(
	module_name => 'App::MtAws',
	author => 'Victor Efimov <vs@vs-dev.com>',
	dist_author => 'Victor Efimov <vs@vs-dev.com>',
	recursive_test_files=>1,
	dist_abstract=>'mt-aws/glacier - Perl Multithreaded Multipart sync to Amazon Glacier',
	license     =>'gpl3',
	script_files => ['bin/mtglacier'], # script_files since M::B 0.18
	meta_add => {
		no_index => {
			namespace => [ 'App::MtAws' ],
		},
	},
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
		'JSON::XS' => 0,


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


		 # File::Temp - for tests we need 0.19, for code probably lower version is OK, perl 5.8.8 ships 0.16, 5.8.9 ships 0.20
		 # TODO: decrease required version
		'File::Temp' => '0.19',

		'File::Spec' => 0,
		'File::stat' => 0,
		'Getopt::Long' => '2.24',


		# distribution 'IO' v 1.22 released with perl 5.8.8, however it does contains IO::{Hnadle|Pipe|Select} versions lower than 1.22
		'IO::Handle' => 0,
		'IO::Pipe' => 0,
		'IO::Select' => 0,

		'List::Util' => '1.11', # needed for Test::Spec, however 1.19 is released with perl 5.8.9
		'POSIX' => 0,
		'PerlIO::encoding' => 0,
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
		'Test::Spec' => '0.46', # we need with() new in 0.46
		'URI' => '1.10', # even ancient LWP versions require at least 1.10, so we use it too
		'HTTP::Daemon' => '1.36',

		# CORE MODULES OR DUAL-LIFE MODULES
		'Data::Dumper' => 0,
		'Time::HiRes' => 0,
		'open' => 0,
		'Scalar::Util' => '1.11',
	},
	recommends => {
		'LWP::Protocol::https' => 6,
	},
	$ENV{MT_NO_HARNESS} ? () : (use_tap_harness    => 1, tap_harness_args   => { jobs => 8 }),
);

$build->create_build_script();
__END__
