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
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::GlacierRequest;
use App::MtAws::Exceptions;
use App::MtAws;
use Data::Dumper;
use TestUtils;

warning_fatal();

describe "new" => sub {
	it "should work" => sub {
		my $g = App::MtAws::GlacierRequest->new({region=>'region', key=>'key', secret=>'secret', protocol=>'http', vault=>'vault'});
		ok $g->isa('App::MtAws::GlacierRequest'), "create correct object";
		ok $g->{service} eq 'glacier';
		ok $g->{account_id} eq '-';
		ok $g->{region} eq 'region';
		ok $g->{key} eq 'key';
		ok $g->{secret} eq 'secret';
		ok $g->{vault} eq 'vault';
		ok $g->{host} eq 'glacier.region.amazonaws.com';
		cmp_set headers('x-amz-glacier-version' => '2012-06-01', 'Host' => $g->{host}), $g->{headers};
	};

	it "should die without region" => sub {
		ok ! eval { App::MtAws::GlacierRequest->new({key=>'key', secret=>'secret', protocol=>'http', vault=>'vault'}) };
	};
	
	it "should die without secret" => sub {
		ok ! eval { App::MtAws::GlacierRequest->new({key=>'key', region=>'region', protocol=>'http', vault=>'vault'}) };
	};
	
	it "should die without protocol" => sub {
		ok ! eval { App::MtAws::GlacierRequest->new({key=>'key', region=>'region', secret=>'secret', vault=>'vault'}) };
	};
	
	it "should not die without vault" => sub {
		ok eval { App::MtAws::GlacierRequest->new({key=>'key', region=>'region', secret=>'secret', protocol=>'http'}) };
	};
	
	it "should die with wrong protocol" => sub {
		ok ! eval { App::MtAws::GlacierRequest->new({key=>'key', region=>'region', secret=>'secret', protocol => 'xyz'}) };
	};
	
	it "should not die with https" => sub {
		ok eval { App::MtAws::GlacierRequest->new({key=>'key', region=>'region', secret=>'secret', protocol => 'https'}) };
	};
};


describe "create_multipart_upload" => sub {
	it "should throw exception if filename too long" => sub {
		my $g = App::MtAws::GlacierRequest->new({region=>'region', key=>'key', secret=>'secret', protocol=>'http', vault=>'vault'});
		my $filename = 'x' x 2000;
		ok ! defined eval { $g->create_multipart_upload(2, $filename, time()); 1 };
		ok is_exception('file_name_too_big');
		is get_exception->{filename}, $filename;
		is exception_message(get_exception),
			"Relative filename \"$filename\" is too big to store in Amazon Glacier metadata. ".
			"Limit is about 700 ASCII characters or 350 2-byte UTF-8 character.";
	};
};

describe "perform_lwp" => sub {
	it "should work with 2xx codes" => sub {
		for my $code (200..209) {
			my $g = App::MtAws::GlacierRequest->new({region=>'region', key=>'key', secret=>'secret', protocol=>'http', vault=>'vault'});
			($g->{method}, $g->{url}) = ('GET', 'test');
			LWP::UserAgent->expects('request')->returns(HTTP::Response->new($code, 'OK'));
			my $resp = $g->perform_lwp();
			is $resp->code, $code;
		}
	};
	describe "throttle" => sub {
		my $retries = 3;
		it "should throttle 408/500" => sub {
			for my $code (qw/408 500/) {
				my $g = App::MtAws::GlacierRequest->new({region=>'region', key=>'key', secret=>'secret', protocol=>'http', vault=>'vault'});
				($g->{method}, $g->{url}) = ('GET', 'test');
				my @throttle_args;
				App::MtAws::GlacierRequest->expects('_max_retries')->any_number->returns($retries);
				App::MtAws::GlacierRequest->expects('throttle')->returns(sub { push @throttle_args, shift } )->exactly($retries);
				LWP::UserAgent->expects('request')->returns(HTTP::Response->new($code))->exactly($retries);
				my $out='';
				my $resp = capture_stdout($out, sub {
					assert_raises_exception sub {
						$g->perform_lwp();
					}, exception 'too_many_tries' => "Request was not successful after $retries retries";
				});
				ok ! defined $resp;
				cmp_deeply [@throttle_args], [(1..$retries)];
				my @matches = $out =~ /PID $$ HTTP $code This might be normal. Will retry \(\d+ seconds spent for request\)/g;
				is scalar @matches, $retries;
			}
		};
		it "should throttle X-Died and read timeout" => sub {
			my $g = App::MtAws::GlacierRequest->new({region=>'region', key=>'key', secret=>'secret', protocol=>'http', vault=>'vault'});
			($g->{method}, $g->{url}) = ('GET', 'test');
			my @throttle_args;
			App::MtAws::GlacierRequest->expects('_max_retries')->any_number->returns($retries);
			App::MtAws::GlacierRequest->expects('throttle')->returns(sub { push @throttle_args, shift } )->exactly($retries);
			LWP::UserAgent->expects('request')->returns(HTTP::Response->new(200, 'OK', [ 'X-Died' => 'Read Timeout at']))->exactly($retries);
			my $out='';
			my $resp = capture_stdout $out, sub {
				assert_raises_exception sub {
					$g->perform_lwp();
				}, exception 'too_many_tries' => "Request was not successful after $retries retries";
			};
			ok ! defined $resp;
			cmp_deeply [@throttle_args], [(1..$retries)];
			my @matches = $out =~ /PID $$ HTTP connection problem. Will retry \(\d+ seconds spent for request\)/g;
			is scalar @matches, $retries;
		};
		it "should catch other codes as unknown errors" => sub {
			for my $code (300..309, 400..407, 409) {
				my $g = App::MtAws::GlacierRequest->new({region=>'region', key=>'key', secret=>'secret', protocol=>'http', vault=>'vault'});
				($g->{method}, $g->{url}) = ('GET', 'test');
				App::MtAws::GlacierRequest->expects('_max_retries')->any_number->returns($retries);
				LWP::UserAgent->expects('request')->returns(HTTP::Response->new($code))->once;
				my $out = '';
				assert_raises_exception sub {
					capture_stderr $out, sub {
						$g->perform_lwp();
					}
				}, exception 'http_unexpected_reply' => "Unexpected reply from remote server";
			}
		};
	};
};

sub header
{
	{ name => $_[0], value => $_[1] }
}

sub headers {
	my @headers;
	while (@_) {
		push @headers, header(splice(@_, 0, 2))
	}
	\@headers;
} 

runtests unless caller;

1;