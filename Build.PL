use strict;
use warnings;
use Module::Build;

use lib qw(lib);

my $build = Module::Build->new(
    module_name => 'Glacier',
    recursive_test_files => 1,
    requires => {
        'File::Find'        => 0,
        'File::Spec'        => 0,
        'Getopt::Long'      => 0,
        'IO::Pipe'          => 0,
        'IO::Select'        => 0,
        'JSON::XS'          => 0,
        'LWP::UserAgent'    => 0,
        'URI'               => 0,
    }
);

$build->create_build_script();
