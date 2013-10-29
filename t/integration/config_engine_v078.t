#!/usr/bin/env perl

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

use strict;
use warnings;
use utf8;
use Test::More tests => 184;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use Test::MockModule;
use Data::Dumper;
use TestUtils;

warning_fatal();

#	print Dumper({errors => $errors, warnings => $warnings, result => $result});

# v0.78 regressions test


my ($default_concurrency, $default_partsize) = (4, 16);
my %misc_opts = ('journal-encoding' => 'UTF-8', 'filenames-encoding' => 'UTF-8', 'terminal-encoding' => 'UTF-8', 'config-encoding' => 'UTF-8', timeout => 180);

# SYNC
for (
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --partsize=$default_partsize!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency --partsize=$default_partsize!,
){
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			dir => '/data/backup',
			concurrency => $default_concurrency,
			partsize => $default_partsize,
			journal => 'journal.log',
			new => 1,
			detect => 'mtime-and-treehash',
			'leaf-optimization' => '1',
		}, "$_ result");
		is_deeply($warnings, ['from-dir deprecated, use dir instead', 'to-vault deprecated, use vault instead'], "$_ warnings text");
	};
}


for (
	qq!sync --key=mykey --secret=mysecret --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
	qq!sync --key=mykey --secret=mysecret --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!sync --key=mykey --secret=mysecret --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log --partsize=$default_partsize!,
	qq!sync --key=mykey --secret=mysecret --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency --partsize=$default_partsize!,
){
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors, "should understand line without config $_");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			dir => '/data/backup',
			new => 1,
			detect => 'mtime-and-treehash',
			concurrency => $default_concurrency,
			partsize => $default_partsize,
			journal => 'journal.log',
			'leaf-optimization' => '1',
		}, "$_ result");
	};
}

for (
	qq!sync --config=glacier.cfg --key=mykey --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
	qq!sync --config=glacier.cfg --key=mykey --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!sync --config=glacier.cfg --key=mykey --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log --partsize=$default_partsize!,
	qq!sync --config=glacier.cfg --key=mykey --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency --partsize=$default_partsize!,
){
	fake_config secret => 'mysecret', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors, "should understand part of config $_");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			config => 'glacier.cfg',
			vault=>'myvault',
			dir => '/data/backup',
			new => 1,
			detect => 'mtime-and-treehash',
			concurrency => $default_concurrency,
			partsize => $default_partsize,
			journal => 'journal.log',
			'leaf-optimization' => '1',
		}, "$_ result");
	}
}

for (
	qq!sync --config=glacier.cfg --key=mykey --secret=newsecret --region myregion --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
){
	fake_config secret => 'mysecret', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors, "command line should override config $_");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'newsecret',
			region => 'myregion',
			protocol => 'http',
			config => 'glacier.cfg',
			vault=>'myvault',
			dir => '/data/backup',
			new => 1,
			detect => 'mtime-and-treehash',
			concurrency => $default_concurrency,
			partsize => $default_partsize,
			journal => 'journal.log',
			'leaf-optimization' => '1',
		}, "$_ result");
	};
}

for (
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=8 --partsize=2!,
	qq!sync --partsize=2 --from-dir /data/backup --config=glacier.cfg --to-vault=myvault --journal=journal.log --concurrency=8 !,
	qq!sync -partsize=2 -from-dir /data/backup -config=glacier.cfg -to-vault=myvault -journal=journal.log -concurrency=8 !,
	qq!sync -partsize 2 -from-dir /data/backup -config glacier.cfg -to-vault=myvault -journal=journal.log -concurrency 8 !,
# TODO: this one will not work
#	qq! -partsize 2 -from-dir /data/backup -config glacier.cfg -to-vault=myvault -journal=journal.log -concurrency 8 sync !,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			dir => '/data/backup',
			concurrency => 8,
			partsize => 2,
			new => 1,
			detect => 'mtime-and-treehash',
			journal => 'journal.log',
			'leaf-optimization' => '1',
		}, "$_ result");
		is_deeply($warnings, ['from-dir deprecated, use dir instead', 'to-vault deprecated, use vault instead'], "$_ warnings text");
	}
}


for (
	qq!sync --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=8 --partsize=2!,
	qq!sync --config=glacier.cfg --to-vault=myvault --journal=journal.log --concurrency=8 --partsize=2!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --journal=journal.log --concurrency=8 --partsize=2!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --concurrency=8 --partsize=2!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( $errors && !$result, "$_ - should catch missed options");
		ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
	}
}

for (
	qq!sync --dir x --config y -journal z -to-va va -conc 9 --partsize=2 extra!,
	qq!sync --from-dir x --config y -journal z -to-va va -conc 9 --partsize=2 extra!,
	qq!sync --from -dir x --config y -journal z -to-va va -conc 9 --partsize=2!,
	qq!sync sync --dir x --config y -journal z -to-va va -conc 9 --partsize=2!,
	qq!sync --dir x --config y -journal z -to-va va extra -conc 9 --partsize=2!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( $errors && !$result, "$_ - should catch non option");
		ok( $errors->[0] =~ /Extra argument/, "$_ - should catch non option");
	}
}
for (
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency --max-number-of-files=42!,
	qq!sync --max-number-of-files=42 --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=42 --partsize=$default_partsize!,
	qq!sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency --max-number-of-files=42 --partsize=$default_partsize!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			dir => '/data/backup',
			concurrency => $default_concurrency,
			'max-number-of-files' => 42,
			new => 1,
			detect => 'mtime-and-treehash',
			partsize => $default_partsize,
			journal => 'journal.log',
			'leaf-optimization' => '1',
		}, "$_ result");
		is_deeply($warnings, ['from-dir deprecated, use dir instead', 'to-vault deprecated, use vault instead'], "$_ warnings text");
	}
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
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
	#	print $errors->[0];
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			config=>'glacier.cfg',
			dir => '/data/backup',
			journal => 'journal.log',
		}, "$_ result");
		cmp_deeply($warnings, set('Option "--to-vault" deprecated for this command','from-dir deprecated, use dir instead', 'to-vault deprecated, use vault instead'),
			"$_ warnings text");
	}
}

for (qw/vault to-vault/){
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', $_ => 'myvault', sub {
		my ($errors, $warnings, $command, $result) =
			config_create_and_parse(split(' ', qq!check-local-hash --config=glacier.cfg --from-dir /data/backup --journal=journal.log!));
		ok( !$errors && $warnings, "error/warnings when $_ is in config");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			config=>'glacier.cfg',
			dir => '/data/backup',
			journal => 'journal.log',
		}, "result when $_ option is in config");
		cmp_deeply($warnings, set('from-dir deprecated, use dir instead'),
			"warnings text when $_ is in config");
	};
}


for (
	qq!check-local-hash --from-dir /data/backup --to-vault=myvault --journal=journal.log!,
	qq!check-local-hash --config=glacier.cfg --to-vault=myvault --journal=journal.log!,
	qq!check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( $errors && !$result, "$_ - should catch missed options");
		ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
	};
}



# RESTORE

for (
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=21 --concurrency=$default_concurrency!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=21!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			dir => '/data/backup',
			concurrency => $default_concurrency,
			'max-number-of-files' => 21,
			journal => 'journal.log',
		}, "$_ result");
		cmp_deeply($warnings, set('to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'), "$_ warnings text");
	}
}


for (
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=21 --concurrency=9!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=9 --max-number-of-files=21!,
	qq!restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal journal.log --max-number-of-files=21 --concurrency=9!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			dir => '/data/backup',
			concurrency => 9,
			'max-number-of-files' => 21,
			journal => 'journal.log',
		}, "$_ result");
		cmp_deeply($warnings, set('to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'), "$_ warnings text");
	};
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
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( $errors && !$result, "$_ - should catch missed options");
		ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
	};
}


# RESTORE-COMPLETED

for (
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log !,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			dir => '/data/backup',
			concurrency => $default_concurrency,
			journal => 'journal.log',
		}, "$_ result");
		cmp_deeply($warnings, set('to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'), "$_ warnings text");
	};
}

for (
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log  --concurrency=9!,
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=9 !,
	qq!restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal journal.log  --concurrency=9!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			dir => '/data/backup',
			concurrency => 9,
			journal => 'journal.log',
		}, "$_ result");
		cmp_deeply($warnings, set('to-vault deprecated, use vault instead','from-dir deprecated, use dir instead'), "$_ warnings text");
	};
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
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( $errors && !$result, "$_ - should catch missed options");
		ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
	};
}





# PURGE-VAULT

for (
	qq!purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=$default_concurrency!,
	qq!purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log !,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			concurrency => $default_concurrency,
			journal => 'journal.log',
		}, "$_ result");
		cmp_deeply($warnings, set('to-vault deprecated, use vault instead','from-dir deprecated, use dir instead', 'Option "--from-dir" deprecated for this command'), "$_ warnings text");
	};
}

for (
	qq!purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log  --concurrency=9!,
	qq!purge-vault --config=glacier.cfg --from-dir /data/backup  --journal=journal.log  --concurrency=9 --to-vault=myvault!,
	qq!purge-vault --config glacier.cfg --from-dir=/data/backup  --journal=journal.log  --concurrency=9 --to-vault=myvault!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( !$errors && $warnings, "$_ error/warnings");
		is_deeply($result, {
			%misc_opts,
			key=>'mykey',
			secret => 'mysecret',
			region => 'myregion',
			protocol => 'http',
			vault=>'myvault',
			config=>'glacier.cfg',
			concurrency => 9,
			journal => 'journal.log',
		}, "$_ result");
		cmp_deeply($warnings, set('to-vault deprecated, use vault instead','from-dir deprecated, use dir instead', 'Option "--from-dir" deprecated for this command'), "$_ warnings text");
	};
}



for (
	qq!purge-vault  --to-vault=myvault --journal=journal.log  --concurrency=9!,
	qq!purge-vault --config=glacier.cfg  --journal=journal.log  --concurrency=9!,
	qq!purge-vault --config=glacier.cfg --to-vault=myvault  --concurrency=9!,
){
	fake_config  sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_));
		ok( $errors && !$result, "$_ - should catch missed options");
		ok( $errors->[0] =~ /Please specify/, "$_ - should catch missed options and give error");
	};
}


1;