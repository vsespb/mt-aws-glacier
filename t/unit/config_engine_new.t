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
use Test::Spec;
use Encode;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::ConfigEngine;
use Data::Dumper;
use TestUtils;

warning_fatal();

sub Context()
{
	$App::MtAws::ConfigEngine::context
}

sub localize(&)
{
	local $App::MtAws::ConfigEngine::context;
	shift->();
}


describe "command" => sub {
	it "should work" => sub {
		localize sub {
			my $code = sub { $_*2 };
			my @res = command 'mycommand', $code;
			ok @res == 0;
			cmp_deeply Context->{commands}->{'mycommand'}, { cb => $code };
		};
	};
	it "should compile with inline subroutine declaration" => sub {
		localize sub {
			command 'mycommand' => sub { $_*2 };
		};
	};
	it "should die if command redefined" => sub {
		localize sub {
			my $code = sub { $_*2 };
			command 'mycommand', $code;
			ok !defined eval { command 'mycommand', $code; 1 };
		};
	};
	it "should die if alias redefined" => sub {
		localize sub {
			my $code = sub { $_*2 };
			command 'firscommand', alias => 'firstalias', $code;
			ok !defined eval { command 'firstalias', $code; 1 };
		};
	};
	it "should work with options" => sub {
		localize sub {
			my $code = sub { $_*2 };
			my @res = command 'mycommand', xyz => 42, def => '24',$code;
			ok @res == 0;
			cmp_deeply Context->{commands}->{'mycommand'}, { cb => $code, xyz => 42, def => 24 };
		};
	};
	describe "alias", sub {
		it "should work with alias option when it's a scalar" => sub {
			localize sub {
				my $code = sub { $_*2 };
				my @res = command 'mycommand', alias => 'abc', abc => 'xyz', $code;
				ok @res == 0;
				cmp_deeply Context->{commands}->{'mycommand'}, { cb => $code, alias => ['abc'], abc => 'xyz' };
				is Context->{aliasmap}->{'abc'}, 'mycommand';
			};
		};
		it "should work with alias option when it's an array" => sub {
			localize sub {
				my $code = sub { $_*2 };
				my @res = command 'mycommand', alias => [qw/abc def/],$code;
				ok @res == 0;
				cmp_deeply Context->{commands}->{'mycommand'}, { cb => $code, alias => ['abc', 'def'] };
				is Context->{aliasmap}->{'abc'}, 'mycommand';
				is Context->{aliasmap}->{'def'}, 'mycommand';
			};
		};
		it "should die if command already defined" => sub {
			localize sub {
				my $code = sub { $_*2 };
				command 'mycommand', $code;
				ok !defined eval { command 'newcommand', alias => 'mycommand', $code; 1 };
			};
		};
		it "should die if alias already defined" => sub {
			localize sub {
				my $code = sub { $_*2 };
				command 'mycommand', alias => 'myalias', $code;
				ok !defined eval { command 'newcommand', alias => 'myalias', $code; 1 };
			};
		};
		it "should die if alias already defined in same statement" => sub {
			localize sub {
				my $code = sub { $_*2 };
				ok !defined eval { command 'newcommand', alias => ['myalias', 'myalias'], $code; 1 };
			};
		};
		it "should die if alias already defined, in case alias is an array" => sub {
			localize sub {
				my $code = sub { $_*2 };
				command 'mycommand', alias => ['myalias1', 'myalias2'], $code;
				ok !defined eval { command 'newcommand', alias => ['myalias3', 'myalias2'], $code; 1 };
			};
		};
	};
	describe "deprecated", sub {
		it "should work with alias option when it's a scalar" => sub {
			localize sub {
				message 'deprecated_command';
				my $code = sub { $_*2 };
				my @res = command 'mycommand', deprecated => 'abc', abc => 'xyz', $code;
				ok @res == 0;
				cmp_deeply Context->{commands}->{'mycommand'}, { cb => $code, deprecated => ['abc'], abc => 'xyz' };
				cmp_deeply Context->{aliasmap}->{'abc'}, 'mycommand';
				ok Context->{deprecated_commands}->{'abc'};
			};
		};
		it "should work with alias option when it's an array" => sub {
			localize sub {
				message 'deprecated_command';
				my $code = sub { $_*2 };
				my @res = command 'mycommand', deprecated => [qw/abc def/],$code;
				ok @res == 0;
				cmp_deeply Context->{commands}->{'mycommand'}, { cb => $code, deprecated => ['abc', 'def'] };
				cmp_deeply Context->{aliasmap}->{'abc'}, 'mycommand';
				cmp_deeply Context->{aliasmap}->{'def'}, 'mycommand';
				ok Context->{deprecated_commands}->{'abc'};
				ok Context->{deprecated_commands}->{'def'};
			};
		};
		it "should die if command already defined" => sub {
			localize sub {
				my $code = sub { $_*2 };
				message 'deprecated_command';
				command 'mycommand', $code;
				ok !defined eval { command 'newcommand', deprecated => 'mycommand', $code; 1 };
			};
		};
		it "should die if alias already defined" => sub {
			localize sub {
				my $code = sub { $_*2 };
				message 'deprecated_command';
				command 'mycommand', alias => 'myalias', $code;
				ok !defined eval { command 'newcommand', deprecated => 'myalias', $code; 1 };
			};
		};
		it "should die if deprecated alias already defined" => sub {
			localize sub {
				message 'deprecated_command';
				my $code = sub { $_*2 };
				command 'mycommand', deprecated => 'myalias', $code;
				ok !defined eval { command 'newcommand', deprecated => 'myalias', $code; 1 };
			};
		};
		it "should die if alias deprecated defined in same statement" => sub {
			localize sub {
				message 'deprecated_command';
				my $code = sub { $_*2 };
				ok !defined eval { command 'newcommand', deprecated => ['myalias', 'myalias'], $code; 1 };
			};
		};
		it "should die if alias deprecated and alias redefined in same statement" => sub {
			localize sub {
				message 'deprecated_command';
				my $code = sub { $_*2 };
				ok !defined eval { command 'newcommand', deprecated => 'myalias', alias => 'myalias', $code; 1 };
				ok !defined eval { command 'newcommand', alias => 'myalias', deprecated => 'myalias', $code; 1 };
			};
		};
		it "should die if alias already defined, in case alias is an array" => sub {
			localize sub {
				message 'deprecated_command';
				my $code = sub { $_*2 };
				command 'mycommand', alias => ['myalias1', 'myalias2'], $code;
				ok !defined eval { command 'newcommand', deprecated => ['myalias3', 'myalias2'], $code; 1 };
			};
		};
	};
};

describe "positional" => sub {
	it "should work" => sub {
		localize sub {
			positional 'myoption';
			cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption', positional => 1}
		}
	};
	it "should allow args" => sub {
		localize sub {
			positional 'myoption', myarg => 42;
			cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption', positional => 1, myarg => 42}
		}
	};
	it "should prohibit overwrite positional" => sub {
		localize sub {
			positional 'myoption', positional => 0;
			cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption', positional => 1}
		}
	};
};

describe "option" => sub {
	it "should work" => sub {
		localize sub {
			option 'myoption';
			cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption'}
		}
	};
	it "should die if option already declared" => sub {
		localize sub {
			local $_ = 'abc';
			option 'myoption';
			ok ! defined eval { option 'myoption'; 1 };
			ok $_ eq 'abc';
		}
	};
	it "should die if positional already declared" => sub {
		localize sub {
			option 'myoption';
			ok ! defined eval { positional 'myoption'; 1 };
		}
	};
	it "positional should die if option already declared" => sub {
		localize sub {
			positional 'myoption';
			ok ! defined eval { option 'myoption'; 1 };
		}
	};
	it "should return option name as scalar" => sub {
		localize sub {
			my $name = option 'myoption';
			ok $name eq 'myoption';
		}
	};
	it "should not be able to overwrite name" => sub {
		localize sub {
			option 'myoption', name => 'xx';
			cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption' };
		}
	};
	describe "alias" => sub {
		it "should work with alias if it's scalar" => sub {
			localize sub {
				message 'already_specified_in_alias';
				is option('myoption', alias => 'oldoption'), 'myoption';
				cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption', alias => ['oldoption']};
				is Context->{optaliasmap}->{'oldoption'}, 'myoption'
			}
		};
		it "should work with alias if it's array" => sub {
			localize sub {
				message 'already_specified_in_alias';
				is option('myoption', alias => ['o1', 'o2']), 'myoption';
				cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption', alias => ['o1', 'o2']};
				is Context->{optaliasmap}->{'o1'}, 'myoption';
				is Context->{optaliasmap}->{'o2'}, 'myoption';
			}
		};
		it "should die if alias redefining option" => sub {
			localize sub {
				message 'already_specified_in_alias';
				option 'o2';
				ok ! defined eval { option('myoption', alias => ['o1', 'o2']); 1 };
			}
		};
		it "should die if alias redefining alias" => sub {
			localize sub {
				message 'already_specified_in_alias';
				option 'old', alias => 'o2';
				ok ! defined eval { option('myoption', alias => ['o1', 'o2']); 1 };
			}
		};
		it "should die if alias redefining alias in same statement" => sub {
			localize sub {
				message 'already_specified_in_alias';
				ok ! defined eval { option('myoption', alias => ['o1', 'o1']); 1 };
			}
		};
		it "should die if alias redefining deprecated" => sub {
			localize sub {
				message 'deprecated_option';
				message 'already_specified_in_alias';
				option 'old', deprecated => 'o2';
				ok ! defined eval { option('myoption', alias => ['o1', 'o2']); 1 };
			}
		};
		it "should die if deprecation redefining deprecation  in same statement" => sub {
			localize sub {
				message 'deprecated_option';
				message 'already_specified_in_alias';
				ok ! defined eval { option('myoption', deprecated => ['o1', 'o1']); 1 };
			}
		};
		it "should die if deprecation redefining alias in same statement" => sub {
			localize sub {
				message 'deprecated_option';
				message 'already_specified_in_alias';
				ok ! defined eval { option('myoption', deprecated => 'o1', alias => 'o1'); 1 };
				ok ! defined eval { option('myoption', alias => 'o1', deprecated => 'o1'); 1 };
			}
		};
	};
	describe "deprecated" => sub {
		it "should work with alias if it's scalar" => sub {
			localize sub {
				message 'deprecated_option';
				message 'already_specified_in_alias';
				is option('myoption', deprecated => 'oldoption'), 'myoption';
				cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption', deprecated => ['oldoption']};
				is Context->{optaliasmap}->{'oldoption'}, 'myoption'
			}
		};
		it "should work with alias if it's array" => sub {
			localize sub {
				message 'deprecated_option';
				message 'already_specified_in_alias';
				is option('myoption', deprecated => ['o1', 'o2']), 'myoption';
				cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption', deprecated => ['o1', 'o2']};
				is Context->{optaliasmap}->{'o1'}, 'myoption';
				is Context->{optaliasmap}->{'o2'}, 'myoption';
			}
		};
		it "should die if deprecated redefining option" => sub {
			localize sub {
				option 'o2';
				message 'deprecated_option';
				message 'already_specified_in_alias';
				ok ! defined eval { option('myoption', deprecated => ['o1', 'o2']); 1 };
			}
		};
		it "should die if deprecated redefining alias" => sub {
			localize sub {
				message 'already_specified_in_alias';
				message 'deprecated_option';
				option 'old', alias => 'o2';
				ok ! defined eval { option('myoption', deprecated => ['o1', 'o2']); 1 };
			}
		};
		it "should die if deprecated redefining deprecated" => sub {
			localize sub {
				message 'deprecated_option';
				message 'already_specified_in_alias';
				option 'old', deprecated => 'o2';
				ok ! defined eval { option('myoption', deprecated => ['o1', 'o2']); 1 };
			}
		};
	};
};

describe "options" => sub {
	it "should work with one argument" => sub {
		localize sub {
			options 'myoption';
			cmp_deeply Context->{options}->{myoption}, {'name' => 'myoption'}
		}
	};
	it "should work with many arguments" => sub {
		localize sub {
			options 'myoption1', 'myoption2';
			cmp_deeply Context->{options}->{myoption1}, {'name' => 'myoption1'};
			cmp_deeply Context->{options}->{myoption2}, {'name' => 'myoption2'};
		}
	};
	it "should die if option is already declared. one argument" => sub {
		localize sub {
			local $_ = 'abc';
			options 'myoption1', 'myoption2';
			ok ! defined eval { options 'myoption1'; 1 };
			ok $_ eq 'abc';
		}
	};
	it "should die if option is already declared. many arguments" => sub {
		localize sub {
			local $_ = 'abc';
			options 'myoption1', 'myoption2';
			ok ! defined eval { options 'myoption1', 'myoption2'; 1 };
			ok $_ eq 'abc';
		}
	};
	it "should return option name as array" => sub {
		localize sub {
			my @res = options 'myoption1', 'myoption2';
			cmp_deeply [@res], ['myoption1', 'myoption2'];
		}
	};
	it "should return array length if several option names are passed and context is scalar" => sub {
		localize sub {
			my $name = options qw/myoption1 myoption2/;
			ok $name eq 2;
		}
	};
};


describe "validation" => sub {
	it "should work" => sub {
		localize sub {
			option 'myoption';
			my $r = validation 'myoption', 'test message', sub { $_ > 10 };
			ok $r eq 'myoption';
			ok scalar @{Context->{options}->{'myoption'}->{validations}} == 1;
			my $v = Context->{options}->{'myoption'}->{validations}->[0];
			cmp_deeply [sort keys %$v], [sort qw/message cb/];
			is $v->{message}, 'test message';
			ok $v->{cb}->() for (11);
			ok !$v->{cb}->() for (10);
		}
	};
	it "should work with options" => sub {
		localize sub {
			option 'myoption';
			my $r = validation 'myoption', 'test message', a => 1, b => 2, sub { $_ > 10 };
			ok $r eq 'myoption';
			ok scalar @{Context->{options}->{'myoption'}->{validations}} == 1;
			my $v = Context->{options}->{'myoption'}->{validations}->[0];
			cmp_deeply [sort keys %$v], [sort qw/a b message cb/];
			is $v->{a}, 1;
			is $v->{b}, 2;
			is $v->{message}, 'test message';
			ok $v->{cb}->() for (11);
			ok !$v->{cb}->() for (10);
		}
	};
	it "should work with options but not override system options" => sub {
		localize sub {
			option 'myoption';
			my $r = validation 'myoption', 'test message', message => 1, cb => 2, sub { $_ > 10 };
			ok $r eq 'myoption';
			ok scalar @{Context->{options}->{'myoption'}->{validations}} == 1;
			my $v = Context->{options}->{'myoption'}->{validations}->[0];
			cmp_deeply [sort keys %$v], [sort qw/message cb/];
			is $v->{message}, 'test message';
			ok $v->{cb}->() for (11);
			ok !$v->{cb}->() for (10);
		}
	};
	it "it should not work if we override_validations" => sub {
		localize sub {
			option 'myoption';
			Context->{override_validations} = {myoption => undef };
			my $r = validation 'myoption', 'test message', sub { $_ > 10 };
			ok ! Context->{options}->{'myoption'}->{validations};
		}
	};
	it "should check if option is declared" => sub {
		localize sub {
			local $_ = 'abc';
			ok ! defined eval { validation 'myoption', 'test message', sub { $_ > 10 }; 1; }
		}
	};
};

describe "assert_option" => sub {
	it "should confess if option not declared" => sub {
		localize sub {
			ok ! defined eval { App::MtAws::ConfigEngine::assert_option for ('myoption'); 1; };
		}
	};
	it "should not confess if option is declared" => sub {
		localize sub {
			option 'myoption';
			is App::MtAws::ConfigEngine::assert_option, Context->{options}->{myoption} for ('myoption');
		}
	};
	it "should not confess if option is declared and option is '0' " => sub {
		localize sub {
			option '0';
			ok defined eval { App::MtAws::ConfigEngine::assert_option for ('0'); 1; };
		}
	};
};

describe "mandatory" => sub {
	it "should check option" => sub {
		localize sub {
			option 'myoption';
			message 'mandatory', "Please specify %option a%";
			App::MtAws::ConfigEngine->expects("assert_option")->once(); # TODO: weird test..
			App::MtAws::ConfigEngine->expects("seen")->once();
			mandatory('myoption2');
		}
	};
	it "should work when mandatory option exists" => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = '123';
			my ($res) = mandatory 'myoption';
			ok $res eq 'myoption';
			ok !defined Context->{errors};
			ok Context->{options}->{myoption}->{seen};
		}
	};
	it "should work when mandatory option missing" => sub {
		localize sub {
			option 'myoption';
			message 'mandatory', "Please specify %option a%";
			my ($res) = mandatory 'myoption';
			ok $res eq 'myoption';
			cmp_deeply Context->{errors}, [ { format => 'mandatory', a => 'myoption' }];
			ok Context->{options}->{myoption}->{seen};
		}
	};
	it "should work with alias" => sub {
		localize sub {
			option 'myoption', alias => 'old';
			message 'mandatory', "Please specify %option a%";
			Context->{options}->{myoption}->{original_option} = 'old';
			my ($res) = mandatory 'myoption';
			ok $res eq 'myoption';
			cmp_deeply Context->{errors}, [ { format => 'mandatory', a => 'old' }];
			ok Context->{options}->{myoption}->{seen};
		}
	};
	it "should work when mandatory option missing and mandatory is nested" => sub {
		localize sub {
			option 'myoption';
			message 'mandatory', "Please specify %option a%";
			my ($res) = mandatory mandatory 'myoption';
			ok $res eq 'myoption';
			cmp_deeply Context->{errors}, [ { format => 'mandatory', a => 'myoption' }];
			ok Context->{options}->{myoption}->{seen};
		}
	};
	it "should check options when several options presents" => sub {
		localize sub {
			message 'mandatory', "Please specify %option a%";
			my @options = ('myoption', 'myoption2');
			options @options;
			App::MtAws::ConfigEngine->expects("assert_option")->exactly(2);
			mandatory @options;
		}
	};
	it "should work when 2 of 2 mandatory option presents" => sub {
		localize sub {
			local $_ = 'abc';
			my @options = ('myoption', 'myoption2');
			options @options;
			Context->{options}->{myoption}->{value} = '123';
			Context->{options}->{myoption2}->{value} = '123';
			my @res = mandatory @options;
			cmp_deeply [@res], [@options];
			ok !defined Context->{errors};
			ok Context->{options}->{myoption}->{seen};
			ok Context->{options}->{myoption2}->{seen};
			ok $_ eq 'abc';
		}
	};
	it "should work when 1 of 2 mandatory option presents" => sub {
		localize sub {
			message 'mandatory', "Please specify %option a%";
			options my @options = ('myoption', 'myoption2');
			Context->{options}->{myoption}->{value} = '123';
			my @res = mandatory @options;
			cmp_deeply [@res], [@options];
			ok defined Context->{errors};
			cmp_deeply Context->{errors}, [ { format => 'mandatory', a => 'myoption2' }];
			ok Context->{options}->{myoption}->{seen};
			ok Context->{options}->{myoption2}->{seen};
		}
	};
	it "should work when 0 of 2 mandatory option presents" => sub {
		localize sub {
			message 'mandatory', "Please specify %option a%";
			options my @options = ('myoption', 'myoption2');
			my @res = mandatory @options;
			cmp_deeply [@res], [@options];
			ok defined Context->{errors};
			cmp_deeply Context->{errors}, [ { format => 'mandatory', a => 'myoption' }, { format => 'mandatory', a => 'myoption2' }];
			ok Context->{options}->{myoption}->{seen};
			ok Context->{options}->{myoption2}->{seen};
		}
	};
	it "should catch if mandatory message is undefined" => sub {
		localize sub {
			options my @options = ('myoption', 'myoption2');
			ok ! defined eval { mandatory @options; 1 };
			ok $@ =~ /mandatory.*undefined/i;
		}
	};
};

describe "optional" => sub {
	describe "one argument" => sub {
		it "should check option" => sub {
			localize sub {
				option 'myoption';
				App::MtAws::ConfigEngine->expects("seen")->once();
				optional('myoption2');
			}
		};
		it "should work when optional option exists" => sub {
			localize sub {
				option 'myoption';
				Context->{options}->{myoption}->{value} = '123';
				my ($res) = optional 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen};
			}
		};
		it "should work when optional option missing" => sub {
			localize sub {
				option 'myoption';
				my ($res) = optional 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};;
				ok Context->{options}->{myoption}->{seen};
			}
		};
	};
	describe "many arguments" => sub {
		it "should check options" => sub {
			localize sub {
				my @options = ('myoption', 'myoption2');
				options @options;
				App::MtAws::ConfigEngine->expects("seen")->exactly(2);
				optional @options;
			}
		};
		it "should work when 2 of 2 optional option presents" => sub {
			localize sub {
				local $_ = 'abc';
				my @options = ('myoption', 'myoption2');
				options @options;
				Context->{options}->{myoption}->{value} = '123';
				Context->{options}->{myoption2}->{value} = '123';
				my @res = optional @options;
				cmp_deeply [@res], [@options];
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen};
				ok Context->{options}->{myoption2}->{seen};
				ok $_ eq 'abc';
			}
		};
		it "should work when 1 of 2 optional option presents" => sub {
			localize sub {
				options my @options = ('myoption', 'myoption2');
				Context->{options}->{myoption}->{value} = '123';
				my @res = optional @options;
				cmp_deeply [@res], [@options];
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen};
				ok Context->{options}->{myoption2}->{seen};
			}
		};
		it "should work when 0 of 2 optional option presents" => sub {
			localize sub {
				options my @options = ('myoption', 'myoption2');
				my @res = optional @options;
				cmp_deeply [@res], [@options];
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen};
				ok Context->{options}->{myoption2}->{seen};
			}
		};
	};
};

describe "deprecated" => sub {
	describe "one argument" => sub {
		it "should check option" => sub {
			localize sub {
				option 'myoption';
				App::MtAws::ConfigEngine->expects("seen")->once();
				optional('myoption2');
			}
		};
		it "should work when deprecated option exists" => sub {
			localize sub {
				message 'option_deprecated_for_command';
				option 'myoption';
				@{Context->{options}->{myoption}}{qw/value source/} = (123, 'option');
				my ($res) = deprecated 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};
				cmp_deeply Context->{warnings}, [{format => 'option_deprecated_for_command', a => 'myoption'}];
				ok Context->{options}->{myoption}->{seen};
				ok ! defined Context->{options}->{myoption}->{value};
			}
		};
		it "should not warn when deprecated option is in config" => sub {
			localize sub {
				message 'option_deprecated_for_command';
				option 'myoption';
				@{Context->{options}->{myoption}}{qw/value source/} = (123, 'config');
				my ($res) = deprecated 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};
				ok !defined Context->{warnings};
				ok Context->{options}->{myoption}->{seen};
				ok ! defined Context->{options}->{myoption}->{value};
			}
		};
		it "should work when deprecated alias option exists" => sub {
			localize sub {
				message 'option_deprecated_for_command';
				option 'myoption', alias => 'old';
				@{Context->{options}->{myoption}}{qw/value source original_option/} = (123, 'option', 'old');
				my ($res) = deprecated 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};
				cmp_deeply Context->{warnings}, [{format => 'option_deprecated_for_command', a => 'old'}];
				ok Context->{options}->{myoption}->{seen};
				ok ! defined Context->{options}->{myoption}->{value};
			}
		};
		it "should die if used with positional argument" => sub {
			localize sub {
				message 'option_deprecated_for_command';
				positional 'myoption';
				@{Context->{options}->{myoption}}{qw/value source/} = (123, 'option');
				ok ! defined eval { deprecated 'myoption'; 1; }
			}
		};
		it "should work when deprecated option missing" => sub {
			localize sub {
				option 'myoption';
				my ($res) = deprecated 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};;
				ok !defined Context->{warnings};
				ok Context->{options}->{myoption}->{seen};
				ok ! defined Context->{options}->{myoption}->{value};
			}
		};
	};
	describe "many arguments" => sub {
		it "should check options" => sub {
			localize sub {
				my @options = ('myoption', 'myoption2');
				options @options;
				App::MtAws::ConfigEngine->expects("seen")->exactly(2)->returns(1);
				deprecated @options;
			}
		};
		it "should work when 2 of 2 optional option presents" => sub {
			localize sub {
				local $_ = 'abc';
				message 'option_deprecated_for_command';
				my @options = ('myoption', 'myoption2');
				options @options;
				@{Context->{options}->{myoption}}{qw/value source/} = (123, 'option');
				@{Context->{options}->{myoption2}}{qw/value source/} = (123, 'option');
				my @res = deprecated @options;
				cmp_deeply [@res], [@options];
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen};
				ok Context->{options}->{myoption2}->{seen};
				cmp_deeply Context->{warnings}, [{format => 'option_deprecated_for_command', a => 'myoption'}, {format => 'option_deprecated_for_command', a => 'myoption2'}];
				ok $_ eq 'abc';
			}
		};
		it "should work when 1 of 2 optional option presents" => sub {
			localize sub {
				message 'option_deprecated_for_command';
				options my @options = ('myoption', 'myoption2');
				@{Context->{options}->{myoption}}{qw/value source/} = (123, 'option');
				my @res = deprecated @options;
				cmp_deeply [@res], [@options];
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen};
				ok Context->{options}->{myoption2}->{seen};
				cmp_deeply Context->{warnings}, [{format => 'option_deprecated_for_command', a => 'myoption'}];
			}
		};
		it "should work when 0 of 2 optional option presents" => sub {
			localize sub {
				message 'option_deprecated_for_command';
				options my @options = ('myoption', 'myoption2');
				my @res = deprecated @options;
				cmp_deeply [@res], [@options];
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen};
				ok Context->{options}->{myoption2}->{seen};
			}
		};
	};
};

describe "validate" => sub {
	it "should check option" => sub {
		localize sub {
			option 'myoption';
			App::MtAws::ConfigEngine->expects("seen")->once()->returns(1);
			validate('myoption2');
		}
	};
	describe "validation is defined" => sub {
		it "should work when validation passed" => sub {
			localize sub {
				local $_ = 'abc';
				validation option('myoption'), 'myerror', sub { $_ > 10 };
				Context->{options}->{myoption}->{value} = '123';
				my ($res) = validate 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated} && Context->{options}->{myoption}->{valid};
				ok $_ eq 'abc';
			}
		};
		it "should work when validation failed" => sub {
			localize sub {
				validation option('myoption'), 'myerror', sub { $_ > 10 };
				Context->{options}->{myoption}->{value} = '7';
				my ($res) = validate 'myoption';
				ok $res eq 'myoption';
				cmp_deeply Context->{errors}, [ { format => 'myerror', a => 'myoption', value => 7 }];
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated};
				ok !Context->{options}->{myoption}->{valid};
			}
		};
		it "should work when validation failed with alias" => sub {
			localize sub {
				validation option('myoption', alias => 'old'), 'myerror', sub { $_ > 10 };
				Context->{options}->{myoption}->{value} = '7';
				Context->{options}->{myoption}->{original_option} = 'old';
				my ($res) = validate 'myoption';
				ok $res eq 'myoption';
				cmp_deeply Context->{errors}, [ { format => 'myerror', a => 'old', value => 7 }];
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated};
				ok !Context->{options}->{myoption}->{valid};
			}
		};
	};
	describe "validation is not defined" => sub {
		it "should work" => sub {
			localize sub {
				option 'myoption';
				Context->{options}->{myoption}->{value} = '123';
				my ($res) = validate 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated} && Context->{options}->{myoption}->{valid};
			}
		};
	};
	describe "option is not present" => sub {
		it "should work" => sub {
			localize sub {
				option 'myoption';
				my ($res) = validate 'myoption';
				ok $res eq 'myoption';
				ok !defined Context->{errors};
				ok Context->{options}->{myoption}->{seen};
				ok ! (Context->{options}->{myoption}->{validated} || Context->{options}->{myoption}->{valid});
			}
		};
	};
	describe "several validations for one option" => sub {
		it "should not perform second validation if stop is true and first failed" => sub {
			localize sub {
				validation option('myoption'), 'myerror', stop => 1, sub { $_ > 10 };
				validation 'myoption', 'myerror2', sub { $_ > 9 };
				Context->{options}->{myoption}->{value} = '1';
				my (@res) = validate qw/myoption/;
				cmp_deeply [@res], [qw/myoption/];
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated};
				ok !Context->{options}->{myoption}->{valid};
				cmp_deeply Context->{errors}, [ { format => 'myerror', a => 'myoption', value =>1 }];
			}
		};
		it "should perform second validation if stop is false and first failed" => sub {
			localize sub {
				validation option('myoption'), 'myerror', sub { $_ > 10 };
				validation 'myoption', 'myerror2', sub { $_ > 9 };
				Context->{options}->{myoption}->{value} = '1';
				my (@res) = validate qw/myoption/;
				cmp_deeply [@res], [qw/myoption/];
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated};
				ok !Context->{options}->{myoption}->{valid};
				cmp_deeply Context->{errors}, [ { format => 'myerror', a => 'myoption', value => 1 }, { format => 'myerror2', a => 'myoption', value => 1 }];
			}
		};
		it "should perform second validation if first passed" => sub {
			localize sub {
				validation option('myoption'), 'myerror', sub { $_ % 2 == 0 };
				validation 'myoption', 'myerror2', sub { $_ > 9 };
				Context->{options}->{myoption}->{value} = 6;
				my (@res) = validate qw/myoption/;
				cmp_deeply [@res], [qw/myoption/];
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated};
				ok !Context->{options}->{myoption}->{valid};
				cmp_deeply Context->{errors}, [ { format => 'myerror2', a => 'myoption', value => 6 }];
			}
		};
	};
	describe "several validations, max. one per option" => sub {
		it "should check option" => sub {
			localize sub {
				options qw/myoption myoption2/;
				App::MtAws::ConfigEngine->expects("seen")->exactly(2)->returns(1);
				validate(qw/myoption2 myoption/);
			}
		};
		it "should work when both failed" => sub {
			localize sub {
				validation option('myoption'), 'myerror', sub { $_ > 10 };
				validation option('myoption2'), 'myerror2', sub { $_ > 9 };
				Context->{options}->{myoption}->{value} = '1';
				Context->{options}->{myoption2}->{value} = '2';
				my (@res) = validate qw/myoption myoption2/;
				cmp_deeply [@res], [qw/myoption myoption2/];
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated};
				ok !Context->{options}->{myoption}->{valid};
				ok Context->{options}->{myoption2}->{seen} && Context->{options}->{myoption2}->{validated};
				ok !Context->{options}->{myoption2}->{valid};
				cmp_deeply Context->{errors}, [ { format => 'myerror', a => 'myoption', value => 1 },
					{ format => 'myerror2', a => 'myoption2', value => 2 }];
			}
		};
		it "error order should match validation order" => sub {
			localize sub {
				validation option('myoption'), 'myerror', sub { $_ > 10 };
				validation option('myoption2'), 'myerror2', sub { $_ > 9 };
				Context->{options}->{myoption}->{value} = '1';
				Context->{options}->{myoption2}->{value} = '2';
				my (@res) = validate qw/myoption2 myoption/;
				cmp_deeply Context->{errors}, [ { format => 'myerror2', a => 'myoption2', value => 2 },
					{ format => 'myerror', a => 'myoption', value => 1 }];
			}
		};
		it "should work when one failed" => sub {
			localize sub {
				validation option('myoption'), 'myerror', sub { $_ > 10 };
				validation option('myoption2'), 'myerror2', sub { $_ > 9 };
				Context->{options}->{myoption}->{value} = '11';
				Context->{options}->{myoption2}->{value} = '2';
				my (@res) = validate qw/myoption myoption2/;
				cmp_deeply [@res], [qw/myoption myoption2/];
				ok Context->{options}->{myoption}->{seen} && Context->{options}->{myoption}->{validated} && Context->{options}->{myoption}->{valid};
				ok Context->{options}->{myoption2}->{seen} && Context->{options}->{myoption2}->{validated};
				ok !Context->{options}->{myoption2}->{valid};
				cmp_deeply Context->{errors}, [ { format => 'myerror2', a => 'myoption2', value => 2 }];
			}
		};
		it "should work when one failed" => sub {
			localize sub {
				options qw/myoption/;
				validation option('myoption2'), 'myerror2', sub { $_ > 9 };
				Context->{options}->{myoption}->{value} = '2';
				Context->{options}->{myoption2}->{value} = '2';
				my (@res) = validate qw/myoption myoption2/;
				cmp_deeply [@res], [qw/myoption myoption2/];
				ok Context->{options}->{myoption}->{seen};
				ok Context->{options}->{myoption2}->{seen};
				cmp_deeply Context->{errors}, [ { format => 'myerror2', a => 'myoption2', value => 2 }];
			}
		};
	};
};

describe "scope" => sub {
	describe "with one argument" => sub {
		it "should work with one scope" => sub {
			localize sub {
				option 'myoption';
				my @res = scope 'myscope', 'myoption';
				cmp_deeply [@res], ['myoption'];
				cmp_deeply Context->{options}->{myoption}->{scope}, ['myscope'];
			}
		};
		it "should work with one two scopes" => sub {
			localize sub {
				option 'myoption';
				my @res = scope 'outer', scope 'inner', 'myoption';
				cmp_deeply [@res], ['myoption'];
				cmp_deeply Context->{options}->{myoption}->{scope}, ['outer', 'inner'];
			}
		};
	};
	describe "with several arguments" => sub {
		it "should check option" => sub {
			localize sub {
				App::MtAws::ConfigEngine->expects("assert_option")->exactly(2);
				scope 'myscope', qw/myoption myoption2/;
			}
		};
		it "should work with one scope" => sub {
			localize sub {
				local $_ = 'abc';
				options qw/o1 o2/;
				my @res = scope 'sc', qw/o1 o2/;
				cmp_deeply [@res], [qw/o1 o2/];
				cmp_deeply Context->{options}->{$_}->{scope}, ['sc'] for qw/o1 o2/;
				ok $_ eq 'abc';
			}
		};
		it "should work with two scopes" => sub {
			localize sub {
				options qw/o1 o2/;
				my @res = scope 'outer', scope 'inner', qw/o1 o2/;
				cmp_deeply [@res], [qw/o1 o2/];
				cmp_deeply Context->{options}->{$_}->{scope}, ['outer', 'inner'] for qw/o1 o2/;
			}
		};
	};
};

describe "present" => sub {
	it "should check option " => sub {
		localize sub {
			local $_ = 'abc';
			option 'myoption';
			option 'myoption2';
			Context->{options}->{myoption}->{value} = 1;
			App::MtAws::ConfigEngine->expects("assert_option")->exactly(2);
			ok present('myoption');
			ok !present('myoption2');
			ok $_ eq 'abc';
		}
	};
	it "should check option when no args" => sub {
		localize sub {
			local $_ = 'abc';
			option 'myoption';
			option 'myoption2';
			Context->{options}->{myoption}->{value} = 1;
			App::MtAws::ConfigEngine->expects("assert_option")->exactly(2);
			ok present for 'myoption';
			ok !present for 'myoption2';
			ok $_ eq 'abc';
		}
	};
	it "should work when option exists " => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = 1;
			ok present('myoption');
		}
	};
	it "should work when option not exists " => sub {
		localize sub {
			option 'myoption';
			ok ! present 'myoption'
		}
	};
};

describe "value" => sub {
	it "should check option " => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = 42;
			App::MtAws::ConfigEngine->expects("assert_option")->once();
			is 42, value('myoption');
		}
	};
	it "should work when option exists " => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = 42;
			is 42, value('myoption');
		}
	};
	it "should work when option exists and empty string" => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = '';
			is '', value('myoption');
		}
	};
	it "should die when option not exists " => sub {
		localize sub {
			option 'myoption';
			ok ! defined eval { value 'myoption'; 1 };
		}
	};
};

describe "valid" => sub {
	it "should check option " => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = 42;
			Context->{options}->{myoption}->{validated} = 1;
			Context->{options}->{myoption}->{valid} = 1;
			App::MtAws::ConfigEngine->expects("assert_option")->once();
			ok valid('myoption');
		}
	};
	it "should work when option valid " => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = 42;
			Context->{options}->{myoption}->{validated} = 1;
			Context->{options}->{myoption}->{valid} = 1;
			ok valid('myoption');
		}
	};
	it "should work when option not valid " => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = 42;
			Context->{options}->{myoption}->{validated} = 1;
			Context->{options}->{myoption}->{valid} = 0;
			ok !valid('myoption');
		}
	};
	it "should die when option not validated " => sub {
		localize sub {
			option 'myoption';
			Context->{options}->{myoption}->{value} = 42;
			ok ! defined eval { ok valid('myoption'); 1 };
		}
	};
};

describe "custom" => sub {
	it "should not redefine option" => sub {
		localize sub {
			option 'myoption';
			ok ! defined eval { custom 'myoption', 42; 1; };
		}
	};
	it "should work " => sub {
		localize sub {
			my $res = custom 'myoption', 42; 1;
			ok $res eq 'myoption';
			cmp_deeply Context->{options}->{myoption}, { name => 'myoption', value => 42, source => 'set', seen => 1 };
		}
	};
};

describe "error" => sub {
	it "should work" => sub {
		localize sub {
			error 'myerror';
			cmp_deeply Context->{errors}, ['myerror'];
		}
	};
	it "should push errors to stack" => sub {
		localize sub {
			error 'myerror';
			error 'myerror2';
			cmp_deeply Context->{errors}, ['myerror', 'myerror2'];
		}
	};
};

describe "warning" => sub {
	it "should work" => sub {
		localize sub {
			warning 'myerror';
			cmp_deeply Context->{warnings}, ['myerror'];
		}
	};
	it "should push warnings to stack" => sub {
		localize sub {
			warning 'mywarning';
			warning 'mywarning2';
			cmp_deeply Context->{warnings}, ['mywarning', 'mywarning2'];
		}
	};
};

describe "error to message" => sub {
	sub error_to_message { &App::MtAws::ConfigEngine::error_to_message };
	
	it "should work without format" => sub {
		ok error_to_message("option is mandatory") eq "option is mandatory";
	};
	it "should work without format with params" => sub {
		ok error_to_message("option is mandatory", a => 1) eq "option is mandatory";
	};
	it "should work with one param" => sub {
		ok error_to_message("%a% is mandatory", a => 42) eq "42 is mandatory";
	};
	it "should work with two params" => sub {
		ok error_to_message("%a% and %b%", a => 1, b => 2) eq "1 and 2";
	};
	it "should work with option" => sub {
		ok error_to_message("%a% and %option b%", a => 'x', b => 'y') eq 'x and "--y"';
		ok error_to_message("%option a% and %option b%", a => 'x', b => 'y') eq '"--x" and "--y"';
		ok error_to_message("%option a% and %b%", a => 'x', b => 'y') eq '"--x" and y';
	};
	it "should work with sprintf formats" => sub {
		ok error_to_message("%a% and %04d b%", a => 'x', b => 10) eq 'x and 0010';
		ok error_to_message("%04d a% and %06d b%", a => '42', b => '24') eq '0042 and 000024';
		ok error_to_message("%04d a% and %b%", a => 42, b => 'y') eq '0042 and y';
	};
	it "should work with alpa, numbers and underscore" => sub {
		ok error_to_message("%a_42% is mandatory", a_42 => 'abc') eq "abc is mandatory";
		ok error_to_message("%option a_42% is mandatory", a_42 => 'abc') eq '"--abc" is mandatory';
		ok error_to_message("%option   a_42% is mandatory", a_42 => 'abc') eq '"--abc" is mandatory';
	};
	it "should confess is variable missing" => sub {
		ok ! defined eval { error_to_message("%a% is mandatory", b => 'abc'); 1 };
		ok ! defined eval { error_to_message("%option a% is mandatory", b => 'abc'); 1 };
		ok ! defined eval { error_to_message("%04d a% is mandatory", b => 42); 1 };
	};
	it "should not confess is there is extra variable" => sub {
		ok defined eval { error_to_message("%a% is mandatory", a => 1, b => 'abc'); 1 };
		ok defined eval { error_to_message("%option a% is mandatory", a => 1, b => 'abc'); 1 };
		ok defined eval { error_to_message("%04d a% is mandatory", a => 1, b => 'abc'); 1 };
	};
};

describe "errors_or_warnings_to_messages" => sub {
	it "should work without params when format defined" => sub {
		my $c = create_engine();
		$c->{messages}->{a} = { format => 'xyz' };
		cmp_deeply [$c->errors_or_warnings_to_messages([{format => 'a'}])], ['xyz'];
	};
	it "should work without params when format not defined" => sub {
		my $c = create_engine();
		cmp_deeply [$c->errors_or_warnings_to_messages(['xyz'])], ['xyz'];
	};
	it "should work with params when format defined" => sub {
		my $c = create_engine();
		$c->{messages}->{a} = { format => 'xyz' };
		App::MtAws::ConfigEngine->expects("error_to_message")->returns(sub{shift;{sort @_}})->once; # kinda hack, we sort hash as array
		cmp_deeply [$c->errors_or_warnings_to_messages([{ format => 'a', x => 'y'}])], [sort (format => 'a', x => 'y')];
	};
	it "should work list" => sub {
		my $c = create_engine();
		$c->{messages}->{a} = {format => 'xyz' };
		cmp_deeply [$c->errors_or_warnings_to_messages([{format => 'a'}, 'abc'])], ['xyz', 'abc'];
	};
	it "should return undef" => sub {
		my $c = create_engine();
		ok ! defined $c->errors_or_warnings_to_messages(undef);
		ok ! defined $c->errors_or_warnings_to_messages();
	};
};

describe "arrayref_or_undef" => sub {
	it "should work" => sub {
		cmp_deeply App::MtAws::ConfigEngine::arrayref_or_undef([1]), [1];
	};
	it "should work with array of undef" => sub {
		cmp_deeply App::MtAws::ConfigEngine::arrayref_or_undef([undef]), [undef];
	};
	it "should work with empty array" => sub {
		ok ! defined App::MtAws::ConfigEngine::arrayref_or_undef([]);
	};
	it "should work with undef" => sub {
		ok ! defined App::MtAws::ConfigEngine::arrayref_or_undef(undef);
	};
	it "should return undef, not empty list" => sub {
		my @a = App::MtAws::ConfigEngine::arrayref_or_undef(undef);
		ok @a == 1;
		ok !defined $a[0];
	};
	it "should return undef, not empty list" => sub {
		my @a = App::MtAws::ConfigEngine::arrayref_or_undef([]);
		ok @a == 1;
		ok !defined $a[0];
	};
};

describe 'message' => sub {
	it "should work" => sub {
		localize sub {
			is message("a", "b"), "a";
			cmp_deeply Context->{messages}{"a"}, {format => "b"};
		};
	};
	it "should work without second argument" => sub {
		localize sub {
			is message("a"), "a";
			cmp_deeply Context->{messages}{"a"}, { format => "a" };
		};
	};
	it "should prohibit redeclaration" => sub {
		localize sub {
			message "a", "b";
			ok ! defined eval { message "a", "c"; 1 };
		};
	};
	it "should prohibit redeclaration even if format is false" => sub {
		localize sub {
			message "a", "0";
			ok ! defined eval { message "a", "0"; 1 };
		};
	};
	it "should not prohibit redeclaration" => sub {
		localize sub {
			message "a", "b", allow_redefine => 1;
			is message("a", "c"), "a";
			cmp_deeply Context->{messages}{"a"}, {format => "c"};
		};
	};
	it "should not prohibit redeclaration twice " => sub {
		localize sub {
			message "a", "b", allow_redefine => 1;
			is message("a", "c", allow_redefine => 1), "a";
			cmp_deeply Context->{messages}{"a"}, {format => "c", allow_redefine => 1};
			is message("a", "d"), "a";
			cmp_deeply Context->{messages}{"a"}, {format => "d"};
		};
	};
	it "should prohibit redeclaration second time " => sub {
		localize sub {
			message "a", "b", allow_redefine => 1;
			is message("a", "c"), "a";
			cmp_deeply Context->{messages}{"a"}, {format => "c"};
			ok ! defined eval { message("a", "d"); 1 };
		};
	};
	it "should not be able to overwrite format" => sub {
		localize sub {
			message "a", "b", format => 'xx';
			cmp_deeply Context->{messages}{"a"}, {format => "b"};
		};
	};
};

describe 'error' => sub {
	it "should work with variables" => sub {
		localize sub {
			message("mymessage", "some text");
			my @res = error("mymessage", a => 1, b => 42);
			ok @res == 0;
			cmp_deeply Context->{errors}, [{ format => "mymessage", a => 1, b => 42}];
		};
	};
	it "should die if message undeclared and variables specified" => sub {
		localize sub {
			message("mymessage", "some text");
			ok !defined eval { error("mymessage1", a => 1, b => 42); 1 };
		};
	};
	it "should not die if message declared, but =0 and variables specified" => sub {
		localize sub {
			message("mymessage", "0");
			my @res = error("mymessage", a => 1, b => 42);;
			ok @res == 0;
		};
	};
	it "should work without variables" => sub {
		localize sub {
			message("mymessage", "some text");
			my @res = error("mymessage");
			ok @res == 0;
			cmp_deeply Context->{errors}, [{ format => "mymessage"}];
		};
	};
	it "should work if message undeclared and no variables specified" => sub {
		localize sub {
			message("mymessage", "some text");
			my @res = error("mymessage1");
			ok @res == 0;
			cmp_deeply Context->{errors}, ["mymessage1"];
		};
	};
};

describe "seen" => sub {
	it "should work" => sub {
		localize sub {
			option 'o1';
			App::MtAws::ConfigEngine::seen('o1');
			cmp_deeply Context->{options}->{o1}, { name => 'o1', seen => 1 };
		};
	};
	it 'should work with \$_' => sub {
		localize sub {
			option 'o1';
			App::MtAws::ConfigEngine::seen for ('o1');
			cmp_deeply Context->{options}->{o1}, { name => 'o1', seen => 1 };
		};
	};
	it "should not work twice" => sub {
		localize sub {
			positional 'o1';
			Context->{positional_tail} = ['a'];
			App::MtAws::ConfigEngine::seen('o1');
			cmp_deeply Context->{positional_tail}, [];
			cmp_deeply Context->{options}->{o1}, { name => 'o1', seen => 1, value => 'a', positional => 1, source => 'positional' };
			App::MtAws::ConfigEngine::seen('o1');
			cmp_deeply Context->{positional_tail}, [];
			cmp_deeply Context->{options}->{o1}, { name => 'o1', seen => 1, value => 'a', positional => 1, source => 'positional' };
		};
	};
	it "should die if option undeclared" => sub {
		localize sub {
			option 'o1';
			ok ! defined eval { App::MtAws::ConfigEngine::seen('o2'); 1 };
		};
	};
	it "should work with positional option" => sub {
		localize sub {
			positional 'o1';
			Context->{positional_tail} = ['a'];
			App::MtAws::ConfigEngine::seen('o1');
			cmp_deeply Context->{options}->{o1}, { name => 'o1', seen => 1, value => 'a', positional => 1, source => 'positional' };
		};
	};
	it "should work with positional option if value missed" => sub {
		localize sub {
			positional 'o1';
			Context->{positional_tail} = [];
			App::MtAws::ConfigEngine::seen('o1');
			cmp_deeply Context->{options}->{o1}, { name => 'o1', seen => 1, positional => 1};
		};
	};
	it "should decode UTF-8" => sub {
		localize sub {
			positional 'o1';
			Context->{positional_tail} = [encode("UTF-8", 'тест')];
			App::MtAws::ConfigEngine::seen('o1');
			cmp_deeply Context->{options}->{o1}, { name => 'o1', seen => 1, positional => 1, source => 'positional', value => 'тест'};
		};
	};
	it "should throw error if broken UTF found" => sub {
		localize sub {
			positional 'o1';
			message 'options_encoding_error', 'bad coding';
			Context->{positional_tail} = ["\xA0"];
			App::MtAws::ConfigEngine::seen('o1');
			cmp_deeply Context->{errors}, [{format => 'options_encoding_error', encoding => 'UTF-8'}];
			cmp_deeply Context->{options}->{o1}, { name => 'o1', seen => 1, positional => 1 };
		};
	};
};

describe 'unflatten_scope' => sub {
	it "should work" => sub {
		my $c = create_engine();
		$c->{options} = {
			a => { value => 1, seen => 1},
			b => { value => 2, scope => ['x'], seen => 1},
		};
		$c->unflatten_scope();
		cmp_deeply $c->{data}, { a => 1, x => { b => 2 }};
		cmp_deeply $c->{options}->{a}, { value => 1, seen => 1}, "it should not autovivify scope";
	};
	it "should not work if option not seen, and we have scope" => sub {
		my $c = create_engine();
		$c->{options} = {
			a => { value => 1, seen => 1},
			b => { value => 2, scope => ['x']},
		};
		$c->unflatten_scope();
		cmp_deeply $c->{data}, { a => 1};
		cmp_deeply $c->{options}->{a}, { value => 1, seen => 1}, "it should not autovivify scope";
	};
	it "should not work if option not seen" => sub {
		my $c = create_engine();
		$c->{options} = {
			a => { value => 1 },
			b => { value => 2, scope => ['x'], seen => 1},
		};
		$c->unflatten_scope();
		cmp_deeply $c->{data}, { x => { b => 2 }};
		cmp_deeply $c->{options}->{a}, { value => 1 }, "it should not autovivify scope";
	};
	it "should not work if option has no value" => sub {
		my $c = create_engine();
		$c->{options} = {
			a => { name => 'a', seen => 1 },
			b => { name => 'b', value => 2, scope => ['x'], seen => 1},
		};
		$c->unflatten_scope();
		cmp_deeply $c->{data}, { x => { b => 2 }};
		cmp_deeply $c->{options}->{a}, { name => 'a', seen => 1 }, "it should not autovivify scope";
	};
	it "should work with nested scopes" => sub {
		my $c = create_engine();
		$c->{options} = {
			a => { value => 1, seen => 1},
			b => { value => 2, scope => ['x', 'y'], seen => 1},
		};
		$c->unflatten_scope();
		cmp_deeply $c->{data}, { a => 1, x => { y => { b => 2 }}};
		cmp_deeply $c->{options}->{a}, { value => 1, seen => 1}, "it should not autovivify scope";
	};
	it "should work with empty data" => sub {
		my $c = create_engine();
		$c->{options} = {};
		$c->unflatten_scope();
		cmp_deeply $c->{data}, {};
	};
};

sub create_engine
{
	App::MtAws::ConfigEngine->new();
}

runtests unless caller;

1;
