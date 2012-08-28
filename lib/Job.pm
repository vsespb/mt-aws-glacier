# mt-aws-glacier - AWS Glacier sync client
# Copyright (C) 2012  Victor Efimov
# vs@vs-dev.com http://vs-dev.com
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

package Job;

use strict;
use warnings;
use Task;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    return $self;
}

# returns "ok" "wait" "ok subtask" "ok replace"
sub get_task
{
	my ($self) = @_;
}

# returns "ok" "ok replace" "done"
sub finish_task
{
	my ($self) = @_;
}
	
1;