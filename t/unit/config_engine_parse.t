#!/usr/bin/perl

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
use Test::More tests => 29;
use Test::Deep;
use lib qw{.. ../..};
use ConfigEngine;
use Test::MockModule;
use Data::Dumper;

no warnings 'redefine';

#
# This time we test both current config and current code together
#

my $max_concurrency = 30;
my $too_big_concurrency = $max_concurrency+1;

my %disable_validations = ( 
	'override_validations' => {
		'journal' => [ ['Journal file not exist' => sub { 1 } ], ],
	},
);

local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion' } };

#	print Dumper({errors => $errors, warnings => $warnings, result => $result});
{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
	));
	#print Dumper({errors => $errors, warnings => $warnings, result => $result});
	ok( $errors && $errors->[0] =~ /specified.*already defined/, 'delect already defined deprecated parameter');
	ok( $warnings && $warnings->[0] =~ /to-vault deprecated, use vault instead/, 'delect already defined deprecated parameter');
}
{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
	));
	ok( !$errors && $warnings && $warnings->[0] =~ /deprecated,\s*use.*instead/, 'warn about deprecated parameter');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	"sync --dir x --config y -journal z -to-va va -conc $too_big_concurrency --partsize=8 "
	));
	ok( $errors && $errors->[0] =~ /Max concurrency/, 'check concurrency range');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=3 '
	));
	ok( $errors && $errors->[0] =~ /must be power of two/, 'check partsize');
}

{
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg --dir /data/backup --to-vault=myvault -journal=journal.log'
	));
#	print Dumper({errors => $errors, warnings => $warnings, result => $result});
	ok( $errors && !$warnings && !$result, "should not accept dir but accept from-dir" );
	is_deeply($errors, ['Error parsing options'], "should not accept dir but accept from-dir");
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result)= ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --vault=myvault -journal=journal.log'
	));
	ok( !$errors && !$warnings && $result && $result->{vault} eq 'myvault', "should override vault in command line" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result)= ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --key=newkey -secret=newsecret --region newregion  --vault=myvault -journal=journal.log'
	));
	ok( !$errors && !$warnings && $result && $result->{key} eq 'newkey' && $result->{secret} eq 'newsecret' && $result->{region} eq 'newregion', "should work without config" );
}


{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  -journal=journal.log'
	));
	ok( !$errors && !$warnings && $result && $result->{vault} eq 'newvault', "should use vault from config" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
	));
	ok( !$errors && $warnings && $result && $result->{vault} eq 'myvault', "should override vault in command line when deprecated-name is used in command line" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	''
	));
	ok( $errors && $errors->[0] eq 'Please specify command', "should catch missing command" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'--myvault x'
	));
	ok( $errors, "should catch missing command even if there are options" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'synx'
	));
	ok( $errors && $errors->[0] eq 'Unknown command', "should catch unknown command" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=3 extra'
	));
	ok( $errors && $errors->[0] =~ /Extra argument/i, "should catch non option" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=3'
	));
	ok( $errors && $errors->[0] eq 'Please specify --config with "secret" option or --secret', "should catch missed secret" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --key a --region b --dir x -journal z -to-va va -conc 9 --partsize=3'
	));
	ok( $errors && $errors->[0] eq 'Please specify --config with "secret" option or --secret', "should catch missed secret without config" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => "mysecret", region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --config a --region b --dir x -to-va va -conc 9 --partsize=4'
	));
	ok( $errors && $errors->[0] eq 'Please specify --journal', "should catch missed journal with config ");
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => "mysecret", region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --key a --secret b --region c --dir x -to-va va -conc 9 --partsize=4'
	));
	ok( $errors && $errors->[0] eq 'Please specify --journal', "should catch missed journal without config ");
}


{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --from -dir x --config y -journal z -to-va va -conc 9 --partsize=3'
	));
	ok( $errors && $errors->[0] =~ /Extra argument/i, "should catch non option 2" );
}

{
	local *ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	for (qw! help -help --help ---help!, qq!  --help !, qq! -help !) {
		my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
		$_
		));
		ok( !$errors && !$warnings && !$result && $command eq 'help', "should catch help [[$_]]" );
	}
}

{
	my $cfg;
	local *ConfigEngine::read_config = sub { $cfg };

	$cfg = { key=>'mykey', secret => 'mysecret', region => 'myregion' };
	my ($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
	));
	ok($result->{concurrency} == 4, "we assume default value is 4");

	$cfg = { key=>'mykey', secret => 'mysecret', region => 'myregion', concurrency => 5 };
	($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log --concurrency=6'
	));
	ok($result->{concurrency} == 6, 'command line option should override config');

	$cfg = { key=>'mykey', secret => 'mysecret', region => 'myregion', concurrency => 5 };
	($errors, $warnings, $command, $result) = ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
	));
	ok($result->{concurrency} == 5, 'but config option should override default');


}


1;