#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 28;
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

# v0.78 regressions test

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=3'
	));
	ok( !$errors && $warnings, "v0.78 regressiong in sync, error/warnings");
	is_deeply($result, {key=>'mykey', secret => 'mysecret', region => 'myregion', vault=>'myvault', config=>'glacier.cfg', dir => '/data/backup', concurrency => 3, journal => 'journal.log'}, 'v0.78 regressiong in sync');
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], 'v0.78 regressiong in sync');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log'
	));
	ok( !$errors && $warnings, "v0.78 regressiong in sync, error/warnings");
	is_deeply($result, {key=>'mykey', secret => 'mysecret', region => 'myregion', vault=>'myvault', config=>'glacier.cfg', dir => '/data/backup', journal => 'journal.log'}, 'v0.78 regressiong in sync');
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], 'v0.78 regressiong in sync');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log'
	));
	ok( !$errors && $warnings, "v0.78 regressiong in check-local-hash, error/warnings" );
	is_deeply($result, {key=>'mykey', secret => 'mysecret', region => 'myregion', config=>'glacier.cfg', dir => '/data/backup', journal => 'journal.log'}, 'v0.78 regressiong in sync');
	is_deeply($warnings, ['to-vault is not needed for this command','from-dir deprecated, use dir instead'], 'v0.78 regressiong in check-local-hash');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log --max-number-of-files=10'
	));
	ok( !$errors && $warnings, "v0.78 regressiong in restore, error/warnings" );
	is_deeply($result, {key=>'mykey', secret => 'mysecret', region => 'myregion', vault=>'myvault', config=>'glacier.cfg', dir => '/data/backup', journal => 'journal.log', 'max-number-of-files' => 10}, 'v0.78 regressiong in restore');
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], 'v0.78 regressiong in restore');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log '
	));
	ok( $errors, "v0.78 regressiong in restore, error/warnings" );
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log'
	));
	ok( !$errors && $warnings, "v0.78 regressiong in restore-completed, error/warnings" );
	is_deeply($result, {key=>'mykey', secret => 'mysecret', region => 'myregion', vault=>'myvault', config=>'glacier.cfg', dir => '/data/backup', journal => 'journal.log'}, 'v0.78 regressiong in restore-completed');
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], 'v0.78 regressiong in restore-completed');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ',
	'purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log'
	));
	ok( !$errors && $warnings, "v0.78 regressiong in purge-vault, error/warnings" );
	is_deeply($result, {key=>'mykey', secret => 'mysecret', region => 'myregion', vault=>'myvault', config=>'glacier.cfg', journal => 'journal.log'}, 'v0.78 regressiong in purge-vault');
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir is not needed for this command'], 'v0.78 regressiong in purge-vault');
}

1;