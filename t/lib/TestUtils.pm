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

package TestUtils;

use FindBin;
use lib "$FindBin::RealBin/../lib";
use strict;
use warnings;

use App::MtAws::ConfigDefinition;
use App::MtAws::ConfigEngine;
use Test::More;

require Exporter;
use base qw/Exporter/;
use Encode;
use Carp;
use IO::Pipe;
use B();
use File::Temp qw/tempdir/;

our %disable_validations;
our @EXPORT = qw/fake_config config_create_and_parse disable_validations no_disable_validations warning_fatal
capture_stdout capture_stderr assert_raises_exception ordered_test test_fast_ok fast_ok with_fork
can_work_with_non_utf8_files get_temp_dir is_iv_without_pv is_posix_root JSON_XS_TRUE JSON_XS_FALSE plan_tests/;

use Test::Deep; # should be last line, after EXPORT stuff, otherwise versions ^(0\.089|0\.09[0-9].*) do something nastly with exports

use constant ALARM_FOR_FORK_TESTS => 30;

# different versions of JSON::XS documents different constants to use
# what is allowed in both cases - is the use of \0 and \1
use constant JSON_XS_TRUE => \1;
use constant JSON_XS_FALSE => \0;

sub warning_fatal
{
	my ($skip_re) = @_;
	$SIG{__WARN__} = sub {
		if (!defined($skip_re) || $_[0] !~ $skip_re) {
			confess "Termination after a warning: $_[0]"
		}
	};
}

sub get_temp_dir
{
	$SIG{INT} = sub { exit(1); }; # Global signal, for cleaning temporary files
	tempdir("__AppMtAws_t_${$}_XXXXXXXX", TMPDIR => 1, CLEANUP => 1); # pid needed cause child processes re-use random number generators
}

sub fake_config(@)
{
	my ($cb, %data) = (pop @_, @_);
	no warnings 'redefine';
	local *App::MtAws::ConfigEngine::read_config = sub { %data ? { %data } : { (key=>'mykey', secret => 'mysecret', region => 'myregion') } };
	disable_validations($cb);
}

sub no_disable_validations
{
	local %disable_validations = ();
	shift->();
}

sub disable_validations
{
	my ($cb, @data) = (pop @_, @_);
	local %disable_validations = @data ?
	(
		'override_validations' => {
			map { $_ => undef } @data
		},
	) :
	(
		'override_validations' => {
			journal => undef,
			secret  => undef,
			key => undef,
			dir => undef,
		},
	);
	$cb->();
}

sub config_create_and_parse(@)
{
#	use Data::Dumper;
#	die Dumper {%disable_validations};
	my $c = App::MtAws::ConfigDefinition::get_config(%disable_validations);
	my $res = $c->parse_options(@_);
	$res->{_config} = $c;
	wantarray ? ($res->{error_texts}, $res->{warning_texts}, $res->{command}, $res->{options}) : $res;
}

sub capture_stdout($&)
{
	local(*STDOUT);
	my $enc = 'UTF-8';
	$_[0]='';# perl 5.8.x issue warning if undefined $out is used in open() below
	open STDOUT, '>', \$_[0] or die "Can't open STDOUT: $!";
	binmode STDOUT, ":encoding($enc)";
	my $res = $_[1]->();
	close STDOUT;
	$_[0] = decode($enc, $_[0], Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	$res;
}

sub capture_stderr($&)
{
	local(*STDERR);
	my $enc = 'UTF-8';
	$_[0]='';# perl 5.8.x issue warning if undefined $out is used in open() below
	open STDERR, '>', \$_[0] or die "Can't open STDERR: $!";
	binmode STDOUT, ":encoding($enc)";
	my $res = $_[1]->();
	close STDERR;
	$_[0] = decode($enc, $_[0], Encode::DIE_ON_ERR|Encode::LEAVE_SRC);
	$res;
}

# TODO: call only as assert_raises_exception sub {}, $e - don't omit sub!
sub assert_raises_exception(&@)
{
	my ($cb, $exception) = @_;
	ok !defined eval { $cb->(); 1 };
	my $err = $@;
	cmp_deeply $err, superhashof($exception);
	return ;
}

our $mock_order_declare;
our $mock_order_realtime;
sub ordered_test
{
	local $mock_order_realtime = 0;
	local $mock_order_declare = 0;
	no warnings 'once';

	local *Test::Spec::Mocks::Expectation::returns_ordered = sub {
		my ($self, $arg) = @_;
		my $n = ++$mock_order_declare;
		if (!defined($arg)) {
			return $self->returns(sub{ is ++$mock_order_realtime, $n; });
		} elsif (ref $arg eq 'CODE') {
			return $self->returns(sub{ is ++$mock_order_realtime, $n; $arg->(@_); });
		} else {
			return $self->returns(sub{ is ++$mock_order_realtime, $n; $arg; });
		}
	};
	shift->();
}

our $test_fast_ok_cnt = undef;

sub fast_ok
{
	my ($cond, $descr) = @_;
	die { FAST_OK_FAILED => $descr } unless $cond;
	$test_fast_ok_cnt--;
	1;
}

#
# test_fast_ok 631, "Message" => sub {};
# args: test plan, message (for case test pass), code block
#
sub test_fast_ok
{
	my ($plan, $message, $cb) = @_;
	local $test_fast_ok_cnt = $plan;
	eval { $cb->(); 1 } or do {
		if ($@ && ref $@ eq ref {} && exists($@->{FAST_OK_FAILED})) {
			my $msg = $@->{FAST_OK_FAILED};
			if (defined($msg) && ref $msg eq 'CODE') {
				ok 0, $msg->();
			} elsif (defined($msg)) {
				ok 0, $msg;
			} else {
				ok 0, "$message - FAILED";
			}
			return;
		} else {
			die $@;
		}
	};
	if ($test_fast_ok_cnt) {
		ok 0, "$message - expected $plan tests, but ran ".($plan - $test_fast_ok_cnt);
	} else {
		ok (1, $message);
	}
}

sub with_fork(&&)
{
	my ($parent_cb, $child_cb) = @_;
	my $ppid = $$;
	my $fromchild = new IO::Pipe;
	my $tochild = new IO::Pipe;

	if (my $pid = fork()) {
		my $child_exited = 0;
		$fromchild->reader();
		$fromchild->autoflush(1);
		$fromchild->blocking(1);
		binmode $fromchild;

		$tochild->writer();
		$tochild->autoflush(1);
		$tochild->blocking(1);
		binmode $tochild;

		alarm ALARM_FOR_FORK_TESTS; # protect from hang in case our test fail
		$parent_cb->($fromchild, $tochild, $pid);
		alarm 0;

		while(wait() != -1 ){};
	} else {
		$fromchild->writer();
		$fromchild->autoflush(1);
		$fromchild->blocking(1);
		binmode $fromchild;

		$tochild->reader();
		$tochild->autoflush(1);
		$tochild->blocking(1);
		binmode $tochild;

		alarm ALARM_FOR_FORK_TESTS; # protect from hang in case our test fail
		$child_cb->($tochild, $fromchild, $ppid);
		alarm 0;

		exit(0);
	}
}


sub can_work_with_non_utf8_files
{
	$^O =~ /^(linux|.*bsd|solaris)$/i;
}

sub get_pv_iv
{
	B::class(B::svref_2object(\$_[0]));
}

sub is_iv_without_pv
{
	&get_pv_iv eq 'IV';
}

our $_cached_posix_root = undef;

sub is_posix_root()
{
	$_cached_posix_root = do {
		if ($^O eq 'cygwin') {
			local ($!, $^E, $@);
			eval {
				require Win32;
				Win32::IsAdminUser();
			}
		} else {
			$> == 0;
		}
	} unless defined $_cached_posix_root;
	$_cached_posix_root;
}


sub plan_tests($$)
{
	my ($n, $cb) = @_;
	if ($ENV{MT_STRESSTEST}){
		plan tests => $ENV{MT_STRESSTEST};
		for (1..$ENV{MT_STRESSTEST}) {
			subtest("d$_", sub {
				plan tests => $n;
				$cb->();
			});
			my (undef, $mem) = `ps -p $$ -o rss`;
			print "MEM $mem\n";
		}
	} else {
		plan tests => $n;
		$cb->();;
	}
}


1;
