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

our $VERSION = '1.102';

use strict;
use warnings;

use Carp;
use Scalar::Util qw/blessed/;
use base 'Exporter';

use constant JOB_RETRY => "MT_J_RETRY";
use constant JOB_OK => "MT_J_OK";
use constant JOB_WAIT => "MT_J_WAIT";
use constant JOB_DONE => "MT_J_DONE";

our @EXPORT = qw/JOB_RETRY JOB_OK JOB_WAIT JOB_DONE state task job parse_result/;

my @valid_codes_a = (JOB_RETRY, JOB_OK, JOB_WAIT, JOB_DONE);
my %valid_codes_h = map { $_ => 1 } @valid_codes_a;
our @valid_fields = qw/code default_code task state job/;

### Instance methods

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	return $self;
}

sub partial_new
{
	my ($class, %args) = @_;
	my $self = $class->new(%args);
	$self->{_type} = 'partial';
	return $self;
}

sub full_new
{
	my ($class, %args) = @_;
	my $self = $class->new(%args);
	$self->{_type} = 'full';
	return $self;
}

### Class methods and DSL

sub is_code($)
{
	$valid_codes_h{shift()};
}


# state STATE
# returns: list with 2 elements
sub state($)
{
	my $class = __PACKAGE__;
	confess unless wantarray;
	return
		$class->partial_new(state => shift),
		$class->partial_new(default_code => JOB_RETRY);

}

# job JOB
# returns: list with 2 elements
sub job(@)
{
	my ($job, $cb) = @_;
	confess unless wantarray;
	return
		JOB_RETRY,
		__PACKAGE__->partial_new(job => { job => $job, $cb ? (cb => $cb) : () } );
}

# task ACTION, sub { ... }
# task ACTION, { k1 => v1, k2 => v2 ... },  sub { ... }
# task ACTION, { k1 => v1, k2 => v2 ... }, \$ATTACHMENT, sub { ... }
# returns: list with 2 elements
sub task(@)
{
	confess unless wantarray;
	my $class = __PACKAGE__;
	confess "at least two args expected" unless @_ >= 2;
	my ($task_action, $cb, $task_args, $attachment) = (shift, pop, @_);

	if (ref $task_action eq ref {}) {
		my $h = $task_action;
		($task_action, $task_args, $attachment) = ($h->{action}, $h->{args}, $h->{attachment} ? $h->{attachment} : ());
	}


	confess "task_args should be hashref" if defined($task_args) && (ref($task_args) ne ref({}));
	confess "no task action" unless $task_action;
	confess "no code ref" unless $cb && ref($cb) eq 'CODE';
	confess "attachment is not reference to scalar: ".ref($attachment) if defined($attachment) && (ref($attachment) ne ref(\""));
	return
		JOB_OK,
		$class->partial_new(task => {
			action => $task_action, cb => $cb, args => $task_args||{}, defined($attachment) ? ( attachment => $attachment) : ()
		});
}


=pod

parse_result(@) input is a list concatenation of one or more of the following entities: TASK, JOB, STATE and CODE

TASK - is a return value of task() function. (i.e. list with 2 items - task object and CODE)
JOB - is a return value of job() function (i.e. list with 2 items - job object and CODE)
STATE - is a return value of state() function (i.e. list with 2 items - state object and default_code object)
CODE - is JOB_xxx code

allowed combinations:

STATE
[STATE, ] (TASK|JOB)
[STATE, ] CODE  (when CODE is not JOB_OK )

=cut

sub parse_result
{
	my $class = __PACKAGE__;
	my $res = {};
	confess "no data" unless @_;
	for my $o (@_) {
		if (blessed($o) && $o->isa($class)) { # anything, but code
			confess "should be partial" unless $o->{_type} eq 'partial';
			my @fields_to_copy = grep { $o->{$_} } @valid_fields;
			confess "should be just one field in the object" if @fields_to_copy != 1;
			my ($field_to_copy) = @fields_to_copy;
			confess "double data: $field_to_copy" if defined($res->{$field_to_copy});
			$res->{$field_to_copy} = $o->{$field_to_copy};
		} elsif (ref($o) eq ref("")) { # code
			confess "code already exists" if defined($res->{code});
			$res->{code} = $o;
		} else {
			confess "bad argument: $o";
		}
	}

	$res->{code} ||= $res->{default_code};
	delete $res->{default_code};

	$res = $class->full_new(%$res);
	confess "no code" unless defined($res->{code});
	confess "code is false" unless $res->{code};
	confess "bad code" unless is_code $res->{code};
	if ($res->{code} eq JOB_OK) {
		confess "no task" unless defined($res->{task});
		confess "no task action" unless defined($res->{task}{action});
		confess "no task cb" unless defined($res->{task}{cb});
		confess "no task args" unless defined($res->{task}{args});
	}
	confess "unexpected task" if ($res->{code} ne JOB_OK && defined($res->{task}));
	$res;
}


1;
