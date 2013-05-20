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
use Test::More tests => 48;
use Test::Deep;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use Test::MockModule;
use Carp;
use Data::Dumper;
use TestUtils;

warning_fatal();

my $mtroot = '/tmp/mt-aws-glacier-tests';



#
# This time we test both current config and current code together
#

my $max_concurrency = 30;
my $too_big_concurrency = $max_concurrency+1;


sub assert_config_throw_error($$$)
{
	my ($config, $errorre, $text) = @_;
	fake_config %$config => sub {
		disable_validations 'journal' => sub {
			my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ', $_ ));
			ok( $errors && $errors->[0] =~ $errorre, $text);
		}
	}
}


{
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
		));
		ok( $errors && $errors->[0] =~ /specified.*already defined/, 'delect already defined deprecated parameter');
		ok( $warnings &&
			($warnings->[0] =~ /to-vault deprecated, use vault instead/) ||
			($warnings->[1] =~ /to-vault deprecated, use vault instead/),
		'delect already defined deprecated parameter');
	}
}
{
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --config y -journal z -to-va va -conc 9 --partsize=2  --from-dir z'
		));
		ok( !$errors && $warnings && $warnings->[0] =~ /deprecated,\s*use.*instead/, 'warn about deprecated parameter');
	}
}

{
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		"sync --dir x --config y -journal z -to-va va -conc $too_big_concurrency --partsize=8 "
		));
		ok( $errors && $errors->[0] =~ /Max concurrency/, 'check concurrency range');
	}
}

{
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=3 '
		));
		ok( $errors && $errors->[0] =~ /must be power of two/, 'check partsize');
	}
}

{
	fake_config sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'purge-vault --config=glacier.cfg --dir /data/backup --to-vault=myvault -journal=journal.log'
		));
		ok( !$errors && $warnings && $result, "should accept dir just like from-dir" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result)= config_create_and_parse(split(' ',
		'purge-vault --config=glacier.cfg  --vault=myvault -journal=journal.log'
		));
		ok( !$errors && !$warnings && $result && $result->{vault} eq 'myvault', "should override vault in command line" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result)= config_create_and_parse(split(' ',
		'purge-vault --key=newkey -secret=newsecret --region newregion  --vault=myvault -journal=journal.log'
		));
		ok( !$errors && !$warnings && $result && $result->{key} eq 'newkey' && $result->{secret} eq 'newsecret' && $result->{region} eq 'newregion', "should work without config" );
	}
}


{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'purge-vault --config=glacier.cfg  -journal=journal.log'
		));
		ok( !$errors && !$warnings && $result && $result->{vault} eq 'newvault', "should use vault from config" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
		));
		ok( !$errors && $warnings && $result && $result->{vault} eq 'myvault', "should override vault in command line when deprecated-name is used in command line" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		''
		));
		ok( $errors && $errors->[0] eq 'Please specify command', "should catch missing command" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		local $SIG{__WARN__} = 'DEFAULT';
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'--myvault x'
		));
		ok( $errors, "should catch missing command even if there are options" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'synx'
		));
		ok( $errors && $errors->[0] =~ /Unknown command/, "should catch unknown command" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=4 extra'
		));
		ok( $errors && $errors->[0] =~ /Extra argument/i, "should catch non option" );
	}
}

{
	fake_config key=>'mykey', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --dir x --config y -journal z -to-va va -conc 9 --partsize=4'
		));
		ok( $errors && $errors->[0] =~ /Please specify.*secret/, "should catch missed secret" );
	}
}

{
	fake_config key=>'mykey', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --key a --region b --dir x -journal z -to-va va -conc 9 --partsize=3'
		));
		ok( $errors && $errors->[0] =~ /Please specify.*secret/, "should catch missed secret without config" );
	}
}

{
	fake_config key=>'mykey', secret => "mysecret", region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --config a --region b --dir x -to-va va -conc 9 --partsize=4'
		));
		ok( $errors && $errors->[0] =~ /Please specify.*journal/, "should catch missed journal with config ");
	}
}

{
	fake_config key=>'mykey', secret => "mysecret", region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --key a --secret b --region c --dir x -to-va va -conc 9 --partsize=4'
		));
		ok( $errors && $errors->[0] =~ /Please specify.*journal/, "should catch missed journal without config ");
	}
}


{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --from -dir x --config y -journal z -to-va va -conc 9 --partsize=4'
		));
		ok( $errors && $errors->[0] =~ /Extra argument/i, "should catch non option 2" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		for (qw! help -help --help ---help!, qq!  --help !, qq! -help !, qq!h!, qq!-h!) {
			my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
			$_
			));
			ok( !$errors && !$warnings && !$result && $command eq 'help', "should catch help [[$_]]" );
		}
	}
}

{
	fake_config key=>'k'x20, secret => 's'x40, region => 'myregion', vault => 'newvault', sub {
		no_disable_validations sub {
			my $file = "$mtroot/journal_t_1";
			unlink $file || confess if -e $file;
			
			my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
			'restore --from-dir x --config y -journal z -to-va va -conc 9 --max-n 1'
			));
			ok( $errors && $errors->[0] =~ /Journal file not found/i, "should catch non existing journal" );
		}
	}
}

for ('restore --from-dir x --config y -journal z -to-va va -conc 9 --max-n 1') {
	assert_config_throw_error { key=>'!'x20, secret => 's'x40, region => 'myregion', vault => 'newvault' }, qr/Invalid format of "key"/, "should catch bad key" ;
	assert_config_throw_error { key=>'a'x21, secret => 's'x40, region => 'myregion', vault => 'newvault' }, qr/Invalid format of "key"/, "should catch bad key" ;
	assert_config_throw_error { key=>'a'x20, secret => 's'x41, region => 'myregion', vault => 'newvault' }, qr/Invalid format of "secret"/, "should catch bad key" ;
	assert_config_throw_error { key=>'a'x20, secret => ' 'x40, region => 'myregion', vault => 'newvault' }, qr/Invalid format of "secret"/, "should catch bad key" ;
	assert_config_throw_error { key=>'a'x20, secret => 'a'x40, region => 'my_region', vault => 'newvault' }, qr/Invalid format of "region"/, "should catch bad key" ;
	assert_config_throw_error { key=>'a'x20, secret => 'a'x40, region => 'x'x80, vault => 'newvault' }, qr/Invalid format of "region"/, "should catch bad key" ;
}



{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		
		my $file = "$mtroot/journal_t_1";
		unlink $file || confess if -e $file;
		
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'sync --from-dir x --config y -journal z -to-va va -conc 9 --max-n 1'
		));
		ok( !$errors, "should allow non-existing journal for sync" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
		));
		ok($result->{concurrency} == 4, "we assume default value is 4");
	};

	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', concurrency => 5, sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log --concurrency=6'
		));
		ok($result->{concurrency} == 6, 'command line option should override config');
	};

	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', concurrency => 5, sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'purge-vault --config=glacier.cfg  --to-vault=myvault -journal=journal.log'
		));
		ok($result->{concurrency} == 5, 'but config option should override default');
	}


}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'create-vault myvault --config=glacier.cfg'
		));
		ok( !$errors, "show allow positional arguments" );
		ok ($command eq 'create-vault');
		ok( $result->{'vault-name'} eq 'myvault', "should parse positional arguments");
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'create-vault --config=glacier.cfg myvault'
		));
		ok( !$errors, "show allow positional arguments after options" );
		ok ($command eq 'create-vault');
		ok( $result->{'vault-name'} eq 'myvault', "should parse positional arguments after options");
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
	
	my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
	'create-vault --config=glacier.cfg'
	));
	ok( $errors && $errors->[0] eq 'Positional argument #1 (vault-name) is mandatory', "show throw error is positional argument is missing" );
	}
}

{
	fake_config key =>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'create-vault --config=glacier.cfg arg1 arg2'
		));
		ok( $errors && $errors->[0] eq 'Extra argument in command line: arg2', "show throw error is there is extra positional argument" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'create-vault --config=glacier.cfg arg1 arg2'
		));
		ok( $errors && $errors->[0] eq 'Extra argument in command line: arg2', "show throw error is there is extra positional argument" );
	}
}

{
	fake_config key=>'mykey', secret => 'mysecret', region => 'myregion', vault => 'newvault', sub {
		my ($errors, $warnings, $command, $result) = config_create_and_parse(split(' ',
		'create-vault --config=glacier.cfg my#vault'
		));
		ok( $errors && $errors->[0] eq 'Vault name should be 255 characters or less and consisting of a-z, A-Z, 0-9, ".", "-", and "_"', "should validate positional arguments" );
	}
}



1;