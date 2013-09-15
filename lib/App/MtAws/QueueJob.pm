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

our $VERSION = '1.051';

use strict;
use warnings;

use Carp;
use App::MtAws::QueueJobResult;

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->{_state} = 'default';
	$self->{_jobs} = [];
	$self->init();
	return $self;
}

sub enter { $_[0]->{_state} = $_[1]; JOB_RETRY }

sub push_job
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
			confess unless $res->isa('App::MtAws::QueueJobResult');
			if ($res->{code} eq JOB_DONE) {
				my $j = pop @{ $self->{_jobs} };
				confess if $j->{cb} && !$j->{cb_proxy};
				$j->{cb_proxy}->($j->{job}) if $j->{cb_proxy};
			} else {
				return $res;
			}
		} else {
			my $method = "on_$self->{_state}";
			my $res = parse_result($self->$method());
			$self->enter($res->{state}) if defined($res->{state});
			$self->push_job($res->{job}) if defined($res->{job});
			if ($res->{task} && $res->{task}{cb}) {
				my $cb = $res->{task}{cb};
				$res->{task}{cb_proxy} = sub {
					if (my @r = $cb->($self)) {
						my $result = parse_result(@r);
						$self->enter($result->{state}) if defined($result->{state});
						confess if $result->{job};
						confess if $result->{task};
					}
				}
			}
			redo if $res->{code} eq JOB_RETRY;
			return $res;
		}
	}
}

sub on_wait { JOB_WAIT }
sub on_done { JOB_DONE }
sub on_die { confess "on_die"; }
sub on_default  { confess "Unimplemented"; }
sub init { confess "Unimplemented"; }

1;
