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
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use File::Temp;
use Carp;
use URI;
use TestUtils;
use Test::More;
use File::Temp ();
warning_fatal();

my $test_size = 2_000_000;

my ($base) = initialize_processes();
	plan tests => 5;

	my $TEMP = File::Temp->newdir();
	my $mtroot = $TEMP->dirname();

	my $tmpfile = "$mtroot/lwp.tmp";
	
	
	sub make_glacier_request
	{
		my ($method, $url, $glacier_options, $merge_keys) = @_;
		my $g = App::MtAws::GlacierRequest->new($glacier_options);
		$g->{$_} = $merge_keys->{$_} for (keys %$merge_keys);
		$g->{method} = $method;
		$g->{url} = '/'.$url;
		local $ENV{MTGLACIER_FAKE_HOST} = $base;
		my $resp = eval {
			$g->perform_lwp();
		};
		return $resp ? ($g, $resp, undef) : ($g, undef, $@);
	}
	
	sub httpd_get_content_length
	{
	    my($c, $req, $size) = @_;
	    $c->send_basic_header(200);
	    
	    my $s = 'x' x $test_size;
	    print $c "Content-Length: $size\015\012";
	    $c->send_crlf;
	    print $c $s;
	}
	
	{
		open F, ">$tmpfile";
		close F;
		my $writer = App::MtAws::HttpFileWriter->new(tempfile => $tmpfile, size => $test_size);
		my (undef, $resp, undef) = make_glacier_request('GET', "content_length/$test_size", {region => 'r', key => 'k', secret => 's', protocol => 'http'}, {writer => $writer});
		is -s $tmpfile, 2_000_000;
		ok($resp->is_success);
	}
	
	{
		no warnings 'redefine';
		local *App::MtAws::GlacierRequest::_max_retries = sub { 1 };
		local *App::MtAws::GlacierRequest::_sleep = sub { };
		my $writer = App::MtAws::HttpFileWriter->new(tempfile => $tmpfile, size => $test_size);
		my ($g, $resp, $err) = make_glacier_request('GET', "content_length/".($test_size-11), {region => 'r', key => 'k', secret => 's', protocol => 'http'}, {writer => $writer});
		is $err->{code}, 'too_many_tries'; # TODO: test with cmp_deep and exception()
		is $g->{last_retry_reason}, 'Unexpected end of data';
		is -s $tmpfile, 2_000_000;
	}
	
	sub httpd_get_quit
	{
	    my($c) = @_;
	    $c->send_error(503, "Bye, bye");
	    exit;  # terminate HTTP server
	}
	
	my $ua = new LWP::UserAgent;
	my $req = new HTTP::Request GET => "http://$base/quit";
	my $resp = $ua->request($req);

sub initialize_processes
{
	if (@ARGV && $ARGV[0] eq 'daemon') {
		require HTTP::Daemon;
		my $d = HTTP::Daemon->new(timeout => 20);
	
		$| = 1;
		print "Please to meet you at: <URL:", $d->url, ">\n";

		while (my $c = $d->accept) {
		my $r = $c->get_request;
		if ($r) {
			my @p = $r->uri->path_segments;
			shift @p;
			my $p = shift @p;
			my $func = lc("httpd_" . $r->method . "_$p");
			if (defined &$func) {
				no strict 'refs';
				&$func($c, $r, @p);
		    } else {
				$c->send_error(404);
			}
		}
		$c = undef;  # close connection
		}
		print STDERR "HTTP Server terminated\n";
		exit;
	} else {
		use Config;
		my $perl = $Config{'perlpath'};
		open(DAEMON, "'$perl' $0 daemon |") or die "Can't exec daemon: $!";
		my $greeting = <DAEMON>;
		$greeting =~ m!<URL:http://([^/]+)/>! or die;
		my $base = $1;
		require LWP::UserAgent;
		require HTTP::Request;
		require App::MtAws::GlacierRequest;
		require App::MtAws;
		return $base;
	}
}

1;
