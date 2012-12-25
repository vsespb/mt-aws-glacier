#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More tests => 150;
use Test::Deep;
use lib qw{.. ../..};
use ConfigEngine;
use Test::MockModule;
use Data::Dumper;

no warnings 'redefine';

local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion' } };

#	print Dumper({errors => $errors, warnings => $warnings, result => $result});

# v0.78 regressions test


my ($default_concurrency, $default_partsize) = (4, 16);

# SYNC
for (
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --partsize=$default_partsize!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency --partsize=$default_partsize!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		dir => '/data/backup',
		concurrency => $default_concurrency,
		partsize => $default_partsize,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], "$_ warnings text");
}

for (
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=8 --partsize=2!,
	qq!sync --partsize=2 --from-dir /data/backup --config=glacier.cfg --to-vault=myvault --journal=journal.log --concurrency=8 !,
	qq!sync -partsize=2 -from-dir /data/backup -config=glacier.cfg -to-vault=myvault -journal=journal.log -concurrency=8 !,
	qq!sync -partsize 2 -from-dir /data/backup -config glacier.cfg -to-vault=myvault -journal=journal.log -concurrency 8 !,
# TODO: this one will not work
#	qq! -partsize 2 -from-dir /data/backup -config glacier.cfg -to-vault=myvault -journal=journal.log -concurrency 8 sync !,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		dir => '/data/backup',
		concurrency => 8,
		partsize => 2,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], "$_ warnings text");
}


for (
	qq!sync --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=8 --partsize=2!,
	qq!sync --config=glacier.cfg --to-vault=myvault --journal=journal.log --concurrency=8 --partsize=2!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --journal=journal.log --concurrency=8 --partsize=2!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --concurrency=8 --partsize=2!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( $errors && !$result, "$_ - should catch missed options");
	ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
}


for (
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency --max-number-of-files=42!,
	qq!sync --max-number-of-files=42 --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=42 --partsize=$default_partsize!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency --max-number-of-files=42 --partsize=$default_partsize!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		dir => '/data/backup',
		concurrency => $default_concurrency,
		'max-number-of-files' => 42,
		partsize => $default_partsize,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], "$_ warnings text");
}

#

# CHECK-LOCAL-HASH

for (
	qq!check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!check-local-hash  --from-dir /data/backup --to-vault=myvault --journal=journal.log --config=glacier.cfg!,
	qq!check-local-hash  --from-dir=/data/backup --to-vault=myvault -journal journal.log --config=glacier.cfg!,
# TODO: this one will not work
#	qq! -partsize 2 -from-dir /data/backup -config glacier.cfg -to-vault=myvault -journal=journal.log -concurrency 8 sync !,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
#	print $errors->[0];
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		config=>'glacier.cfg',
		dir => '/data/backup',
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault is not needed for this command','from-dir deprecated, use dir instead'], "$_ warnings text");
}

for (
	qq!check-local-hash --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!check-local-hash --config=glacier.cfg --to-vault=myvault --journal=journal.log!,
	qq!check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( $errors && !$result, "$_ - should catch missed options");
	ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
}



# RESTORE

for (
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=21 --concurrency=$default_concurrency!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=21!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		dir => '/data/backup',
		concurrency => $default_concurrency,
		'max-number-of-files' => 21,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], "$_ warnings text");
}


for (
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=21 --concurrency=9!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=9 --max-number-of-files=21!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal journal.log --max-number-of-files=21 --concurrency=9!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		dir => '/data/backup',
		concurrency => 9,
		'max-number-of-files' => 21,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], "$_ warnings text");
}

for (
	qq!restore --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=21!,
	qq!restore --config=glacier.cfg --to-vault=myvault --journal=journal.log --max-number-of-files=21!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --journal=journal.log --max-number-of-files=21!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --max-number-of-files=21!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log !,

	qq!restore --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=21 --concurrency=9!,
	qq!restore --config=glacier.cfg --to-vault=myvault --journal=journal.log --max-number-of-files=21 --concurrency=9!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --journal=journal.log --max-number-of-files=21 --concurrency=9!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --max-number-of-files=21 --concurrency=9!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=9!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( $errors && !$result, "$_ - should catch missed options");
	ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
}


# RESTORE-COMPLETED

for (
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log !,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		dir => '/data/backup',
		concurrency => $default_concurrency,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], "$_ warnings text");
}

for (
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log  --concurrency=9!,
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=9 !,
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal journal.log  --concurrency=9!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		dir => '/data/backup',
		concurrency => 9,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'], "$_ warnings text");
}


for (
	qq!restore --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!restore --config=glacier.cfg --to-vault=myvault --journal=journal.log!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --journal=journal.log!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log !,

	qq!restore --from-dir /data/backup --to-vault=myvault --journal=journal.log--concurrency=9!,
	qq!restore --config=glacier.cfg --to-vault=myvault --journal=journal.log --concurrency=9!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --journal=journal.log --concurrency=9!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --concurrency=9!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=9!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( $errors && !$result, "$_ - should catch missed options");
	ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
}





# PURGE-VAULT

for (
	qq!purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
	qq!purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log !,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		concurrency => $default_concurrency,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir is not needed for this command'], "$_ warnings text");
}


for (
	qq!purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log  --concurrency=9!,
	qq!purge-vault --config=glacier.cfg --from-dir /data/backup  --journal=journal.log  --concurrency=9 --to-vault=myvault!,
	qq!purge-vault --config glacier.cfg --from-dir=/data/backup  --journal=journal.log  --concurrency=9 --to-vault=myvault!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( !$errors && $warnings, "$_ error/warnings");
	is_deeply($result, {
		key=>'mykey',
		secret => 'mysecret',
		region => 'myregion',
		vault=>'myvault',
		config=>'glacier.cfg',
		concurrency => 9,
		journal => 'journal.log',
	}, "$_ result");
	is_deeply($warnings, ['to-vault deprecated, use vault instead','from-dir is not needed for this command'], "$_ warnings text");
}


for (
	qq!purge-vault  --to-vault=myvault --journal=journal.log  --concurrency=9!,
	qq!purge-vault --config=glacier.cfg  --journal=journal.log  --concurrency=9!,
	qq!purge-vault --config=glacier.cfg --to-vault=myvault  --concurrency=9!,
){
	my ($errors, $warnings, $command, $result) = ConfigEngine->new()->parse_options(split(' ', $_));
	ok( $errors && !$result, "$_ - should catch missed options");
	ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
}


1;