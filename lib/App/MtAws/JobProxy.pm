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

package App::MtAws::JobProxy;

our $VERSION = '1.055';

use strict;
use warnings;
use utf8;

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	$self->{job}||die;
	bless $self, $class;
	return $self;
}

# returns "ok" "wait" "ok subtask"
sub get_task
{
	my ($self, @a) = @_;
	my @r = $self->{job}->get_task(@a);
	
	if ($r[0] eq 'ok replace'){
		$self->{job} = $r[1];
		@r = $self->{job}->get_task(@a);
	}
	return @r;
}

# returns "ok", "done"
sub finish_task
{
	my ($self, @a) = @_;
	my @res = $self->{job}->finish_task(@a);
	if ($res[0] eq 'ok replace'){
		$self->{job} = $res[1];
		return ("ok");
	} else {
		return @res;
	}
}

sub will_do
{
	# TODO: does it make any sense to call will_do() after job replaced?? probably yes..
	# for example we can dump pending jobs anytime.. 
	shift->{job}->will_do();
}
	
1;
