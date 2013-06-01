use strict;
use warnings;
use Module::Build;

use lib qw(lib);


die "OS unsupported\n" if ($^O eq 'MSWin32');

my $build = Module::Build->new(
	module_name => 'App::MtAws',
	author => 'Victor Efimov',
	dist_author => 'Victor Efimov',
	recursive_test_files=>1,
	dist_abstract=>'mt-aws/glacier - Perl Multithreaded Multipart sync to Amazon Glacier',
	license     =>'gpl3',
	scripts => ['mtglacier'],
	meta_add => {
		no_index => {
			directory => [ qw( lib/App/MtAws ) ],
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
		
		'LWP::UserAgent' => 6,
		'LWP::Protocol::https' => 0, # actually can be listed as optional
		'JSON::XS' => 0,
		'HTTP::Request::Common' => 0, # required by LWP::UserAgent, but I use i directly also


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
		'Test::Spec' => 0,

		# CORE MODULES OR DUAL-LIFE MODULES
		'Data::Dumper' => 0,
		'open' => 0,
		
	}
);

$build->create_build_script();
__END__
