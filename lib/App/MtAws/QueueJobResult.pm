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

package App::MtAws::QueueJobResult;

our $VERSION = '1.051';

use strict;
use warnings;

use Carp;
use base 'Exporter';

use constant JOB_RETRY => "MT_J_RETRY";
use constant JOB_OK => "MT_J_OK";
use constant JOB_WAIT => "MT_J_WAIT";
use constant JOB_DONE => "MT_J_DONE";

our @EXPORT = qw/JOB_RETRY JOB_OK JOB_WAIT JOB_DONE state task parse_result/;

my @valid_codes_a = (JOB_RETRY, JOB_OK, JOB_WAIT, JOB_DONE);
my %valid_codes_h = map { $_ => 1 } @valid_codes_a;

### Instance methods

sub partial_new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->{_type} = 'partial';
	return $self;
}

sub full_new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->{_type} = 'full';
	return $self;
}

### Class methods and DSL

sub is_code($)
{
	$valid_codes_h{shift()};
}


sub state($)
{
	__PACKAGE__->partial_new( state => shift);
}

sub task(@)
{
	confess "at least two args expected" unless @_ >= 2;
	my $task_action = shift;
	my $cb = pop;
	my ($task_args, $attachment) = @_;
	confess "task_args should be hashref" if defined($task_args) && (ref($task_args) ne ref({}));
	confess "no task action" unless $task_action;
	confess "no code ref" unless $cb && ref($cb) eq 'CODE';
	confess "attachment is not reference to scalar: ".ref($attachment) if defined($attachment) && (ref($attachment) ne ref(\""));
	return __PACKAGE__->partial_new(code => JOB_OK, task_action => $task_action, task_cb => $cb,
		task_args => $task_args||{}, defined($attachment) ? ( task_attachment => $attachment) : ());
}


# return WAIT, "my_task", 1, 2, 3, sub { ... }
sub parse_result
{
	my $res = {};
	confess "no data" unless @_;
	for (@_) {
		if (ref($_) ne ref("") && $_->isa(__PACKAGE__)) {
			confess "should be partial" unless delete $_->{_type} eq 'partial';
			confess "double code" if defined($res->{code}) && defined($_->{code});
			%$res = (%$res, %$_);
		} elsif (ref($_) eq ref("")) {
			confess "code already exists" if defined($res->{code});
			$res->{code} = $_;
		}
	}

	$res->{code} = JOB_RETRY if ($res->{state} && !$res->{code});

	$res = __PACKAGE__->full_new(%$res);
	confess "no code" unless defined($res->{code});
	confess "bad code" unless is_code $res->{code};
	if ($res->{code} eq JOB_OK) {
		confess "no action" unless defined($res->{task_action});
		confess "no cb" unless defined($res->{task_cb});
		confess "no args" unless defined($res->{task_args});
	}
	if ($res->{code} ne JOB_OK) {
		confess "unexpected action" if defined($res->{task_action});
		confess "unexpected cb" if defined($res->{task_cb});
		confess "unexpected args" if defined($res->{task_args});
	}
	$res;
}


1;
