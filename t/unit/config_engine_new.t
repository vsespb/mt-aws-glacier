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
use Test::Spec;
use lib qw{../lib ../../lib};
use App::MtAws::ConfigEngineNew;
use Data::Dumper;

sub context()
{
	$App::MtAws::ConfigEngineNew::context
}

sub localize(&)
{
	local $App::MtAws::ConfigEngineNew::context;
	shift->();
}


describe "option" => sub {
	it "should work" => sub {
		localize sub {
			option 'myoption';
			cmp_deeply context->{options}->{myoption}, {'name' => 'myoption'}
		}
	};
	it "should not overwrite existing option" => sub {
		localize sub {
			local $_ = 'abc';
			option 'myoption';
			cmp_deeply context->{options}->{myoption}, {'name' => 'myoption'};
			mandatory 'myoption';
			cmp_deeply context->{options}->{myoption}, {'name' => 'myoption', 'seen' => 1};
			option 'myoption';
			cmp_deeply context->{options}->{myoption}, {'name' => 'myoption', 'seen' => 1};
			ok $_ eq 'abc';
		}
	};
	it "should return option name as scalar" => sub {
		localize sub {
			my $name = option 'myoption';
			ok $name eq 'myoption';
		}
	};
};

describe "options" => sub {
	it "should work with one argument" => sub {
		localize sub {
			options 'myoption';
			cmp_deeply context->{options}->{myoption}, {'name' => 'myoption'}
		}
	};
	it "should work with many arguments" => sub {
		localize sub {
			options 'myoption1', 'myoption2';
			cmp_deeply context->{options}->{myoption1}, {'name' => 'myoption1'};
			cmp_deeply context->{options}->{myoption2}, {'name' => 'myoption2'};
		}
	};
	it "should not overwrite existing options" => sub {
		localize sub {
			local $_ = 'abc';
			options 'myoption1', 'myoption2';
			cmp_deeply context->{options}->{myoption1}, {'name' => 'myoption1'};
			cmp_deeply context->{options}->{myoption2}, {'name' => 'myoption2'};
			mandatory 'myoption1';
			cmp_deeply context->{options}->{myoption1}, {'name' => 'myoption1', 'seen' => 1};
			options 'myoption1';
			cmp_deeply context->{options}->{myoption1}, {'name' => 'myoption1', 'seen' => 1};
			ok $_ eq 'abc';
		}
	};
	it "should return option name as array" => sub {
		localize sub {
			my @res = options 'myoption1', 'myoption2';
			cmp_deeply [@res], ['myoption1', 'myoption2'];
		}
	};
	it "should return option name as scalar if just one option is specified" => sub {
		localize sub {
			my $name = options 'myoption';
			ok $name eq 'myoption';
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
			ok scalar @{context->{options}->{'myoption'}->{validations}} == 1;
			my $v = context->{options}->{'myoption'}->{validations}->[0];
			cmp_deeply [sort keys %$v], [sort qw/message cb/]; 
			ok $v->{message} eq 'test message';
			ok $v->{cb}->() for (11);
			ok !$v->{cb}->() for (10);
		}
	};
	it "should work without option" => sub {
		localize sub {
			local $_ = 'abc';
			my $r = validation 'myoption', 'test message', sub { $_ > 10 };
			ok $r eq 'myoption';
			ok context->{options}->{'myoption'};
			cmp_deeply [sort keys %{context->{options}->{'myoption'}}], [sort qw/name validations/];
			ok 'myoption' eq context->{options}->{'myoption'}->{name};
			ok scalar @{context->{options}->{'myoption'}->{validations}} == 1;
			ok $_ eq 'abc';
		}
	};
};

describe "assert_option" => sub {
	it "should confess if option not declared" => sub {
		localize sub {
			ok ! defined eval { App::MtAws::ConfigEngineNew::assert_option for ('myoption'); 1; };
		}
	};
	it "should not confess if option is declared" => sub {
		localize sub {
			option 'myoption';
			ok defined eval { App::MtAws::ConfigEngineNew::assert_option for ('myoption'); 1; };
		}
	};
	it "should not confess if option is declared and option is '0' " => sub {
		localize sub {
			option '0';
			ok defined eval { App::MtAws::ConfigEngineNew::assert_option for ('0'); 1; };
		}
	};
};

describe "mandatory" => sub {
	it "should check option" => sub {
		localize sub {
			option 'myoption';
			App::MtAws::ConfigEngineNew->expects("assert_option")->once();
			mandatory('myoption2');
		}
	};
	it "should work when mandatory option exists" => sub {
		localize sub {
			option 'myoption';
			context->{options}->{myoption}->{value} = '123';
			my ($res) = mandatory 'myoption';
			ok $res eq 'myoption';
			ok !defined context->{errors};
			ok context->{options}->{myoption}->{seen};
		}
	};
	it "should work when mandatory option missing" => sub {
		localize sub {
			option 'myoption';
			my ($res) = mandatory 'myoption';
			ok $res eq 'myoption';
			cmp_deeply context->{errors}, [ { format => 'mandatory', a => 'myoption' }];
			ok context->{options}->{myoption}->{seen};
		}
	};
	it "should work when mandatory option missing and mandatory is nested" => sub {
		localize sub {
			option 'myoption';
			my ($res) = mandatory mandatory 'myoption';
			ok $res eq 'myoption';
			cmp_deeply context->{errors}, [ { format => 'mandatory', a => 'myoption' }];
			ok context->{options}->{myoption}->{seen};
		}
	};
	it "should check options when several options presents" => sub {
		localize sub {
			my @options = ('myoption', 'myoption2');
			options @options;
			App::MtAws::ConfigEngineNew->expects("assert_option")->exactly(2);
			mandatory @options;
		}
	};
	it "should work when 2 of 2 mandatory option presents" => sub {
		localize sub {
			local $_ = 'abc';
			my @options = ('myoption', 'myoption2');
			options @options;
			context->{options}->{myoption}->{value} = '123';
			context->{options}->{myoption2}->{value} = '123';
			my @res = mandatory @options;
			cmp_deeply [@res], [@options];
			ok !defined context->{errors};
			ok context->{options}->{myoption}->{seen};
			ok context->{options}->{myoption2}->{seen};
			ok $_ eq 'abc';
		}
	};
	it "should work when 1 of 2 mandatory option presents" => sub {
		localize sub {
			options my @options = ('myoption', 'myoption2');
			context->{options}->{myoption}->{value} = '123';
			my @res = mandatory @options;
			cmp_deeply [@res], [@options];
			ok defined context->{errors};
			cmp_deeply context->{errors}, [ { format => 'mandatory', a => 'myoption2' }];
			ok context->{options}->{myoption}->{seen};
			ok context->{options}->{myoption2}->{seen};
		}
	};
	it "should work when 0 of 2 mandatory option presents" => sub {
		localize sub {
			options my @options = ('myoption', 'myoption2');
			my @res = mandatory @options;
			cmp_deeply [@res], [@options];
			ok defined context->{errors};
			cmp_deeply context->{errors}, [ { format => 'mandatory', a => 'myoption' }, { format => 'mandatory', a => 'myoption2' }];
			ok context->{options}->{myoption}->{seen};
			ok context->{options}->{myoption2}->{seen};
		}
	};
};

describe "optional" => sub {
	describe "one argument" => sub {
		it "should check option" => sub {
			localize sub {
				option 'myoption';
				App::MtAws::ConfigEngineNew->expects("assert_option")->once();
				optional('myoption2');
			}
		};
		it "should work when optional option exists" => sub {
			localize sub {
				option 'myoption';
				context->{options}->{myoption}->{value} = '123';
				my ($res) = optional 'myoption';
				ok $res eq 'myoption';
				ok !defined context->{errors};
				ok context->{options}->{myoption}->{seen};
			}
		};
		it "should work when optional option missing" => sub {
			localize sub {
				option 'myoption';
				my ($res) = optional 'myoption';
				ok $res eq 'myoption';
				ok !defined context->{errors};;
				ok context->{options}->{myoption}->{seen};
			}
		};
	};
	describe "many arguments" => sub {
		it "should check options" => sub {
			localize sub {
				my @options = ('myoption', 'myoption2');
				options @options;
				App::MtAws::ConfigEngineNew->expects("assert_option")->exactly(2);
				optional @options;
			}
		};
		it "should work when 2 of 2 optional option presents" => sub {
			localize sub {
				local $_ = 'abc';
				my @options = ('myoption', 'myoption2');
				options @options;
				context->{options}->{myoption}->{value} = '123';
				context->{options}->{myoption2}->{value} = '123';
				my @res = optional @options;
				cmp_deeply [@res], [@options];
				ok !defined context->{errors};
				ok context->{options}->{myoption}->{seen};
				ok context->{options}->{myoption2}->{seen};
				ok $_ eq 'abc';
			}
		};
		it "should work when 1 of 2 optional option presents" => sub {
			localize sub {
				options my @options = ('myoption', 'myoption2');
				context->{options}->{myoption}->{value} = '123';
				my @res = optional @options;
				cmp_deeply [@res], [@options];
				ok !defined context->{errors};
				ok context->{options}->{myoption}->{seen};
				ok context->{options}->{myoption2}->{seen};
			}
		};
		it "should work when 0 of 2 optional option presents" => sub {
			localize sub {
				options my @options = ('myoption', 'myoption2');
				my @res = optional @options;
				cmp_deeply [@res], [@options];
				ok !defined context->{errors};
				ok context->{options}->{myoption}->{seen};
				ok context->{options}->{myoption2}->{seen};
			}
		};
	};
};

describe "validate" => sub {
	it "should check option" => sub {
		localize sub {
			option 'myoption';
			App::MtAws::ConfigEngineNew->expects("assert_option")->once();
			validate('myoption2');
		}
	};
	describe "validation is defined" => sub {
		it "should work when validation passed" => sub {
			localize sub {
				local $_ = 'abc';
				validation 'myoption', 'myerror', sub { $_ > 10 };
				context->{options}->{myoption}->{value} = '123';
				my ($res) = validate 'myoption';
				ok $res eq 'myoption';
				ok !defined context->{errors};
				ok context->{options}->{myoption}->{seen};
				ok $_ eq 'abc';
			}
		};
		it "should work when validation failed" => sub {
			localize sub {
				validation 'myoption', 'myerror', sub { $_ > 10 };
				context->{options}->{myoption}->{value} = '7';
				my ($res) = validate 'myoption';
				ok $res eq 'myoption';
				cmp_deeply context->{errors}, [ { format => 'myerror', a => 'myoption' }];
				ok context->{options}->{myoption}->{seen};
			}
		};
	};
	describe "validation is not defined" => sub {
		it "should work" => sub {
			localize sub {
				option 'myoption';
				context->{options}->{myoption}->{value} = '123';
				my ($res) = validate 'myoption';
				ok $res eq 'myoption';
				ok !defined context->{errors};
				ok context->{options}->{myoption}->{seen};
			}
		};
	};
	describe "several validation" => sub {
		it "should check option" => sub {
			localize sub {
				options qw/myoption myoption2/;
				App::MtAws::ConfigEngineNew->expects("assert_option")->exactly(2);
				validate(qw/myoption2 myoption/);
			}
		};
		it "should work when both failed" => sub {
			localize sub {
				options qw/myoption/;
				validation 'myoption', 'myerror', sub { $_ > 10 };
				validation 'myoption2', 'myerror2', sub { $_ > 9 };
				context->{options}->{myoption}->{value} = '1';
				context->{options}->{myoption2}->{value} = '2';
				my (@res) = validate qw/myoption myoption2/;
				cmp_deeply [@res], [qw/myoption myoption2/];
				ok context->{options}->{myoption}->{seen};
				ok context->{options}->{myoption2}->{seen};
				cmp_deeply context->{errors}, [ { format => 'myerror', a => 'myoption' }, { format => 'myerror2', a => 'myoption2' }];
			}
		};
		it "error order should match validation order" => sub {
			localize sub {
				options qw/myoption/;
				validation 'myoption', 'myerror', sub { $_ > 10 };
				validation 'myoption2', 'myerror2', sub { $_ > 9 };
				context->{options}->{myoption}->{value} = '1';
				context->{options}->{myoption2}->{value} = '2';
				my (@res) = validate qw/myoption2 myoption/;
				cmp_deeply context->{errors}, [ { format => 'myerror2', a => 'myoption2' }, { format => 'myerror', a => 'myoption' }];
			}
		};
		it "should work when one failed" => sub {
			localize sub {
				options qw/myoption/;
				validation 'myoption', 'myerror', sub { $_ > 10 };
				validation 'myoption2', 'myerror2', sub { $_ > 9 };
				context->{options}->{myoption}->{value} = '11';
				context->{options}->{myoption2}->{value} = '2';
				my (@res) = validate qw/myoption myoption2/;
				cmp_deeply [@res], [qw/myoption myoption2/];
				ok context->{options}->{myoption}->{seen};
				ok context->{options}->{myoption2}->{seen};
				cmp_deeply context->{errors}, [ { format => 'myerror2', a => 'myoption2' }];
			}
		};
		it "should work when one failed" => sub {
			localize sub {
				options qw/myoption/;
				validation 'myoption2', 'myerror2', sub { $_ > 9 };
				context->{options}->{myoption}->{value} = '2';
				context->{options}->{myoption2}->{value} = '2';
				my (@res) = validate qw/myoption myoption2/;
				cmp_deeply [@res], [qw/myoption myoption2/];
				ok context->{options}->{myoption}->{seen};
				ok context->{options}->{myoption2}->{seen};
				cmp_deeply context->{errors}, [ { format => 'myerror2', a => 'myoption2' }];
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
				cmp_deeply context->{options}->{myoption}->{scope}, ['myscope'];
			}
		};
		it "should work with one two scopes" => sub {
			localize sub {
				option 'myoption';
				my @res = scope 'outer', scope 'inner', 'myoption';
				cmp_deeply [@res], ['myoption'];
				cmp_deeply context->{options}->{myoption}->{scope}, ['outer', 'inner'];
			}
		};
	};
	describe "with several arguments" => sub {
		it "should check option" => sub {
			localize sub {
				App::MtAws::ConfigEngineNew->expects("assert_option")->exactly(2);
				scope 'myscope', qw/myoption myoption2/;
			}
		};
		it "should work with one scope" => sub {
			localize sub {
				local $_ = 'abc';
				options qw/o1 o2/;
				my @res = scope 'sc', qw/o1 o2/;
				cmp_deeply [@res], [qw/o1 o2/];
				cmp_deeply context->{options}->{$_}->{scope}, ['sc'] for qw/o1 o2/;
				ok $_ eq 'abc';
			}
		};
		it "should work with two scopes" => sub {
			localize sub {
				options qw/o1 o2/;
				my @res = scope 'outer', scope 'inner', qw/o1 o2/;
				cmp_deeply [@res], [qw/o1 o2/];
				cmp_deeply context->{options}->{$_}->{scope}, ['outer', 'inner'] for qw/o1 o2/;
			}
		};
	};
};

describe "present" => sub {
	it "should check option " => sub {
		localize sub {
			local $_ = 'abc';
			option 'myoption';
			context->{options}->{myoption}->{value} = 1;
			App::MtAws::ConfigEngineNew->expects("assert_option")->once();
			ok present('myoption');
			ok $_ eq 'abc';
		}
	};
	it "should work when option exists " => sub {
		localize sub {
			option 'myoption';
			context->{options}->{myoption}->{value} = 1;
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
			cmp_deeply context->{options}->{myoption}, { name => 'myoption', value => 42, source => 'set' };
		}
	};
};

describe "error" => sub {
	it "should work" => sub {
		localize sub {
			error 'myerror';
			cmp_deeply context->{errors}, ['myerror']; 
		}
	};
	it "should push errors to stack" => sub {
		localize sub {
			error 'myerror';
			error 'myerror2';
			cmp_deeply context->{errors}, ['myerror', 'myerror2']; 
		}
	};
};

describe "error to message" => sub {
	sub error_to_message { &App::MtAws::ConfigEngineNew::error_to_message };
	
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
runtests unless caller;

1;