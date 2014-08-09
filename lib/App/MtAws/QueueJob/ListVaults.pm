# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2014  Victor Efimov
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

package App::MtAws::QueueJob::ListVaults;

our $VERSION = '1.120';

use strict;
use warnings;
use Carp;

use App::MtAws::QueueJobResult;
use App::MtAws::Glacier::ListVaults;
use base 'App::MtAws::QueueJob';

sub init
{
	my ($self) = @_;
	$self->{marker} = undef;
	$self->{all_vaults} = [];
	$self->enter("list");
}

sub on_list
{
	my ($self) = @_;
	return state "wait", task "list_vaults", {  marker => $self->{marker} } => sub {
		my ($args) = @_;

		my ($marker, @vaults) = App::MtAws::Glacier::ListVaults->new( $args->{response} || confess )->get_list_vaults();
		push @{$self->{all_vaults}}, @vaults;
		if ($marker) {
			$self->{marker} = $marker;
			return state 'list';
		} else {
			return state 'done';
		}
	}
}

1;
