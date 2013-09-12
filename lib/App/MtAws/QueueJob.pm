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

package App::MtAws::QueueJob;

use strict;
use warnings;

use Carp;
use base 'Exporter';

use constant JOB_RETRY => "MT_J_RETRY";
use constant JOB_OK => "MT_J_OK";
use constant JOB_WAIT => "MT_J_WAIT";
use constant JOB_DONE => "MT_J_DONE";
use constant JOB_RESULT_CLASS => 'App::MtAws::QueueJob::Result';

our @EXPORT = qw/JOB_RETRY JOB_OK JOB_WAIT JOB_DONE JOB_RESULT_CLASS state task/;

sub _is_code
{
	my $c = shift;
	$c =~ /\AMT_J/ && grep { $_ eq $c } (JOB_RETRY, JOB_OK, JOB_WAIT, JOB_DONE);
}


sub state($)
{
	bless { state => shift }, JOB_RESULT_CLASS;
}

sub task(@)
{
	my $cb = pop;
	my $task_action = shift;
	confess unless $cb && ref($cb) eq ref(sub {});
	my @args = @_;
	return bless { code => JOB_OK, task_action => $task_action, task_cb => $cb, task_args => \@args }, JOB_RESULT_CLASS;
}

# return WAIT, "my_task", 1, 2, 3, sub { ... }
sub parse_result
{
	my $res = {};
	for (@_) {
		if (ref($_) eq JOB_RESULT_CLASS) {
			confess "double code" if defined($res->{code}) && defined($_->{code});
			%$res = (%$res, %$_);
		} elsif (ref($_) eq ref("")) {
			confess "code already exists" if defined($res->{code});
			$res->{code} = $_;
		}
	}
	bless $res, JOB_RESULT_CLASS;
	confess "no code" unless defined($res->{code});
	confess "bad code" unless _is_code($res->{code});
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

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->{_state} = 'default';
	$self->{_jobs} = [];
	return $self;
}

sub enter { $_[0]->{_state} = $_[1]; JOB_RETRY }

sub push
{
	my ($self, $job, $cb) = @_;
	push @{ $self->{_jobs} }, { job => $job, cb => $cb };
	JOB_RETRY;
}

sub next
{
	my ($self) = @_;

	while () {
		if ( @{ $self->{_jobs} } ) {
			my $res = $self->{_jobs}->[-1]->{job}->next();
			confess unless $res->{MT_RESULT};
			if ($res->{code} eq JOB_DONE) {
				my $j = pop @{ $self->{_jobs} };
				$j->{cb}->($j->{job}) if $j->{cb};
			} else {
				return $res;
			}
		} else {
			my $method = "on_$self->{_state}";
			my $res = parse_result($self->$method());
			$self->enter($res->{state}) if defined($res->{state});
			redo if $res->{code} eq JOB_RETRY;
			return $res;
		}
	}
}

sub on_wait
{
	JOB_WAIT
}

sub on_done
{
	JOB_DONE
}

sub on_die
{
	confess;
}

1;
