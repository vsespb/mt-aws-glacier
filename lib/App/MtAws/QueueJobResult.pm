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

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	return $self;
}


### Class methods and DSL

sub is_code($)
{
	$valid_codes_h{shift()};
}


sub state($)
{
	__PACKAGE__->new( state => shift);
}

sub task(@)
{
	my $cb = pop;
	my $task_action = shift;
	confess unless $cb && ref($cb) eq 'CODE';
	my @args = @_;
	return __PACKAGE__->new(code => JOB_OK, task_action => $task_action, task_cb => $cb, task_args => \@args);
}


# return WAIT, "my_task", 1, 2, 3, sub { ... }
sub parse_result
{
	my $res = {};
	for (@_) {
		if ($_->isa(__PACKAGE__)) {
			confess "double code" if defined($res->{code}) && defined($_->{code});
			%$res = (%$res, %$_);
		} elsif (ref($_) eq ref("")) {
			confess "code already exists" if defined($res->{code});
			$res->{code} = $_;
		}
	}
	$res = __PACKAGE__->new(%$res);
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
