use strict;
use warnings;
use Module::Build;

use lib qw(lib);

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
		'perl' => 5.008008,
		'Digest::SHA' => 0,
		'LWP::UserAgent' => 6,
		'LWP::Protocol::https' => 0,
		'JSON::XS' => 0,
	},
	build_requires => {
		'TAP::Harness' => 0,
		'Test::Deep' => 0,
		'Test::MockModule' => 0,
		'DateTime' => 0,
		'Test::Spec' => 0,
		'MIME::Base64' => 0,
	}
);

$build->create_build_script();
__END__
distribution_type
