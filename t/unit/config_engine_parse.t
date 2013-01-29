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
use Test::More tests => 43;
use Test::Deep;
use lib qw{../lib ../../lib};
use App::MtAws::ConfigEngine;
use Test::MockModule;
use Carp;
use Data::Dumper;

my $mtroot = '/tmp/mt-aws-glacier-tests';

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

local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion' } };

#	print Dumper({errors => $errors, warnings => $warnings, result => $result});
{
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
	));
	#print Dumper({errors => $errors, warnings => $warnings, result => $result});
	ok( $errors && $errors->[0] =~ /specified.*already defined/, 'delect already defined deprecated parameter');
	ok( $warnings && $warnings->[0] =~ /to-vault deprecated, use vault instead/, 'delect already defined deprecated parameter');
}
{
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
	));
	ok( !$errors && $warnings && $warnings->[0] =~ /deprecated,\s*use.*instead/, 'warn about deprecated parameter');
}

{
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	"sync --dir x --config y -journal z -to-va va -conc $too_big_concurrency --partsize=8 "
	));
	ok( $errors && $errors->[0] =~ /Max concurrency/, 'check concurrency range');
}

{
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=3 '
	));
	ok( $errors && $errors->[0] =~ /must be power of two/, 'check partsize');
}

{
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg --dir /data/backup --to-vault=myvault -journal=journal.log'
	));
#	print Dumper({errors => $errors, warnings => $warnings, result => $result});
	ok( $errors && !$warnings && !$result, "should not accept dir but accept from-dir" );
	is_deeply($errors, ['Error parsing options'], "should not accept dir but accept from-dir");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result)= App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --vault=myvault -journal=journal.log'
	));
	ok( !$errors && !$warnings && $result && $result->{vault} eq 'myvault', "should override vault in command line" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result)= App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --key=newkey -secret=newsecret --region newregion  --vault=myvault -journal=journal.log'
	));
	ok( !$errors && !$warnings && $result && $result->{key} eq 'newkey' && $result->{secret} eq 'newsecret' && $result->{region} eq 'newregion', "should work without config" );
}


{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  -journal=journal.log'
	));
	ok( !$errors && !$warnings && $result && $result->{vault} eq 'newvault', "should use vault from config" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
	));
	ok( !$errors && $warnings && $result && $result->{vault} eq 'myvault', "should override vault in command line when deprecated-name is used in command line" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	''
	));
	ok( $errors && $errors->[0] eq 'Please specify command', "should catch missing command" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'--myvault x'
	));
	ok( $errors, "should catch missing command even if there are options" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'synx'
	));
	ok( $errors && $errors->[0] eq 'Unknown command', "should catch unknown command" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=3 extra'
	));
	ok( $errors && $errors->[0] =~ /Extra argument/i, "should catch non option" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=3'
	));
	ok( $errors && $errors->[0] eq 'Please specify --secret OR add "secret=..." into the config file', "should catch missed secret" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --key a --region b --dir x -journal z -to-va va -conc 9 --partsize=3'
	));
	ok( $errors && $errors->[0] eq 'Please specify --secret OR specify --config and put "secret=..." into the config file', "should catch missed secret without config" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => "mysecret", region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --config a --region b --dir x -to-va va -conc 9 --partsize=4'
	));
	ok( $errors && $errors->[0] eq 'Please specify --journal', "should catch missed journal with config ");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => "mysecret", region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --key a --secret b --region c --dir x -to-va va -conc 9 --partsize=4'
	));
	ok( $errors && $errors->[0] eq 'Please specify --journal', "should catch missed journal without config ");
}


{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'sync --from -dir x --config y -journal z -to-va va -conc 9 --partsize=3'
	));
	ok( $errors && $errors->[0] =~ /Extra argument/i, "should catch non option 2" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	for (qw! help -help --help ---help!, qq!  --help !, qq! -help !, qq!h!, qq!-h!) {
		my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
		$_
		));
		ok( !$errors && !$warnings && !$result && $command eq 'help', "should catch help [[$_]]" );
	}
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	
	my $file = "$mtroot/journal_t_1";
	unlink $file || confess if -e $file;
	
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new()->parse_options(split(' ',
	'restore --from-dir x --config y -journal z -to-va va -conc 9 --max-n 1'
	));
	ok( $errors && $errors->[0] =~ /Journal file not found/i, "should catch non existing journal $errors->[0]" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	
	my $file = "$mtroot/journal_t_1";
	unlink $file || confess if -e $file;
	
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new()->parse_options(split(' ',
	'sync --from-dir x --config y -journal z -to-va va -conc 9 --max-n 1'
	));
	ok( !$errors, "should allow non-existing journal for sync" );
}

{
	my $cfg;
	local *App::MtAws::ConfigEngine::read_config = sub { $cfg };

	$cfg = { key=>'mykey', secret => 'mysecret', region => 'myregion' };
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
	));
	ok($result->{concurrency} == 4, "we assume default value is 4");

	$cfg = { key=>'mykey', secret => 'mysecret', region => 'myregion', concurrency => 5 };
	($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log --concurrency=6'
	));
	ok($result->{concurrency} == 6, 'command line option should override config');

	$cfg = { key=>'mykey', secret => 'mysecret', region => 'myregion', concurrency => 5 };
	($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new(%disable_validations)->parse_options(split(' ',
	'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
	));
	ok($result->{concurrency} == 5, 'but config option should override default');


}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new()->parse_options(split(' ',
	'create-vault myvault --config=glacier.cfg'
	));
	ok( !$errors, "show allow positional arguments" );
	ok ($command eq 'create-vault');
	ok( $result->{'vault-name'} eq 'myvault', "should parse positional arguments");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new()->parse_options(split(' ',
	'create-vault --config=glacier.cfg myvault'
	));
	ok( !$errors, "show allow positional arguments after options" );
	ok ($command eq 'create-vault');
	ok( $result->{'vault-name'} eq 'myvault', "should parse positional arguments after options");
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new()->parse_options(split(' ',
	'create-vault --config=glacier.cfg'
	));
	ok( $errors && $errors->[0] eq 'Please specify another argument in command line: vault-name', "show throw error is positional argument is missing" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new()->parse_options(split(' ',
	'create-vault --config=glacier.cfg arg1 arg2'
	));
	ok( $errors && $errors->[0] eq 'Extra argument in command line: arg2', "show throw error is there is extra positional argument" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new()->parse_options(split(' ',
	'create-vault --config=glacier.cfg arg1 arg2'
	));
	ok( $errors && $errors->[0] eq 'Extra argument in command line: arg2', "show throw error is there is extra positional argument" );
}

{
	local *App::MtAws::ConfigEngine::read_config = sub { { key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault' } };
	
	my ($errors, $warnings, $command, $result) = App::MtAws::ConfigEngine->new()->parse_options(split(' ',
	'create-vault --config=glacier.cfg my#vault'
	));
	ok( $errors && $errors->[0] eq 'Vault name should be 255 characters or less and consisting of a-z, A-Z, 0-9, ".", "-", and "_"', "should validate positional arguments" );
}

1;