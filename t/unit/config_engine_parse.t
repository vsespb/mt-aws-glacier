#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 9;
use Test::Deep;
use lib qw{.. ../..};
use ConfigEngine;
use Test::MockModule;
use Data::Dumper;

no warnings 'redefine';

local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion' } };

#	print Dumper({errors => $errors, warnings => $warnings, result => $result});
{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
	));
	#print Dumper({errors => $errors, warnings => $warnings, result => $result});
	ok( $errors && $errors->[0] =~ /specified.*already defined/, 'delect already defined deprecated parameter');
	ok( $warnings && $warnings->[0] =~ /to-vault deprecated, use vault instead/, 'delect already defined deprecated parameter');
}
{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
	));
	ok( !$errors && $warnings && $warnings->[0] =~ /deprecated,\s*use.*instead/, 'warn about deprecated parameter');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 11 --partsize=8 '
	));
	ok( $errors && $errors->[0] =~ /Max concurrency/, 'check concurrency range');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=3 '
	));
	ok( $errors && $errors->[0] =~ /must be power of two/, 'check partsize');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'purge-vault --config=glacier.cfg --dir /data/backup --to-vault=myvault -journal=journal.log'
	));
#	print Dumper({errors => $errors, warnings => $warnings, result => $result});
	ok( $errors && !$warnings && !$result, "should not accept dir but accept from-dir" );
	is_deeply($errors, ['Error parsing options'], "should not accept dir but accept from-dir");
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result)= ConfigEngine->new()->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --vault=myvault -journal=journal.log'
	));
	ok( !$errors && !$warnings && $result && $result->{vault} eq 'myvault', "should override vault in command line" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  -journal=journal.log'
	));
	ok( !$errors && !$warnings && $result && $result->{vault} eq 'newvault', "should use vault from config" );
}

if (0) {
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
	));
	print "ZZZ:".Dumper({errors => $errors, warnings => $warnings, result => $result});
	ok( !$errors && !$warnings && $result && $result->{vault} eq 'myvault', "should override vault in command line when deprecated-name is used in command line" );
}


1;