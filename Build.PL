
use 5.008008; # minumum perl version is 5.8.8, ancient cpan clients will ignore 'requires/perl' below
use strict;
use warnings;
use Module::Build;

use lib qw(lib);


die "OS unsupported\n" if ($^O eq 'MSWin32');

my $build = Module::Build->new(
	module_name => 'App::MtAws',
	use_tap_harness    => 1,
	tap_harness_args   => { jobs => 8 },
	author => 'Victor Efimov <vs@vs-dev.com>',
	dist_author => 'Victor Efimov <vs@vs-dev.com>',
	recursive_test_files=>1,
	dist_abstract=>'mt-aws/glacier - Perl Multithreaded Multipart sync to Amazon Glacier',
	license     =>'gpl3',
	scripts => ['mtglacier'],
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
		
		'LWP' => 5,
		'HTTP::Request::Common' => 5, # required by LWP::UserAgent, but I use i directly also
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
		'File::Spec' => 0,
		'File::stat' => 0,
		'Getopt::Long' => 0,
		'IO::Handle' => 0,
		'IO::Pipe' => 0,
		'IO::Select' => 0,
		'List::Util' => 0,
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
		'TAP::Harness' => 0,
		'Test::Deep' => 0,
		'Test::MockModule' => 0,
		'DateTime' => 0,
		'Test::Spec' => 0.46,
		'URI' => 0,
		'HTTP::Daemon' => 5,

		# CORE MODULES OR DUAL-LIFE MODULES
		'Data::Dumper' => 0,
		'Time::HiRes' => 0,
		'open' => 0,
		
	},
	recommends => {
		'LWP::Protocol::https' => 6,
	}
);

$build->create_build_script();
__END__
