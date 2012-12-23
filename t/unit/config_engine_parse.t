#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 3;
use Test::Deep;
use lib qw{.. ../..};
use ConfigEngine;
use Test::MockModule;
use Data::Dumper;



# Dumper(errors => $errors, warnings => $warnings, result => $result)
{
	my ($errors, $warnings, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
	));
	ok( $errors && $errors->[0] =~ /specified.*already defined/, 'delect already defined deprecated parameter');
}
{
	my ($errors, $warnings, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
	));
	ok( !$errors && $warnings && $warnings->[0] =~ /deprecated,\s*use.*instead/, 'warn about deprecated parameter');
}

{
	my ($errors, $warings, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 11 --partsize=2 '
	));
	ok( $errors && $errors->[0] =~ /Max concurrency/, 'check concurrency range');
}

1;