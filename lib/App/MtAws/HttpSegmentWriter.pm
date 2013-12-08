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

package App::MtAws::HttpWriter;

our $VERSION = '1.101';

use strict;
use warnings;
use utf8;
use Carp;
use App::MtAws::TreeHash;


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->initialize();
	return $self;
}

sub initialize
{
	my ($self) = @_;
	$self->{write_threshold} = 2*1024*1024;
}

sub reinit
{
	my ($self, $size) = @_;
	$self->{size}=$size;
	$self->{totalsize}=0;
	$self->{total_commited_length} = $self->{pending_length} = $self->{total_length} = 0;
	$self->{buffer} = '';
}

sub add_data
{
	my $self = $_[0];
	return unless defined($_[1]);
	my $len = length($_[1]);
	$self->{buffer} .= $_[1];
	$self->{pending_length} += $len;
	$self->{total_length} += $len;
	if ($self->{pending_length} > $self->{write_threshold}) {
		$self->_flush();
	}
	1;
}

sub _flush
{
	confess "not implemented";
}

sub treehash
{
	undef;
}

sub _flush_buffers
{
	my ($self, @files) = @_;
	my $len = length($self->{buffer});
	for my $fh (@files) {
		print $fh $self->{buffer} or confess "cant write to file $!";
	}
	if (my $th = $self->treehash) {
		$th->eat_data_any_size($self->{buffer});
	}
	$self->{total_commited_length} += $len;
	$self->{buffer} = '';
	$self->{pending_length} = 0;
	$len;
}

sub finish
{
	my ($self) = @_;
	$self->_flush();
	$self->{total_commited_length} == $self->{total_length} or confess;
	return ($self->{total_length} && ($self->{total_length} == $self->{size})) ? ('ok') : ('retry', 'Unexpected end of data');
}

package App::MtAws::HttpSegmentWriter;

our $VERSION = '1.101';

use strict;
use warnings;
use utf8;
use App::MtAws::Utils;
use Fcntl qw/SEEK_SET LOCK_EX/;
use Carp;
use base qw/App::MtAws::HttpWriter/;


# when file not found/etc error happen, it can mean Temp file deleted by another process, so we
# don't need to throw error, most likelly signal will arrive in a few milliseconds
sub delayed_confess(@)
{
	sleep 2;
	confess @_;
}


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->SUPER::initialize();
	$self->initialize();
	return $self;
}

sub initialize
{
	my ($self) = @_;
	defined($self->{filename}) or confess;
	defined($self->{tempfile}) or confess;
	defined($self->{position}) or confess;
}

sub reinit
{
	my $self = shift;
	$self->{incr_position} = 0;
	$self->{treehash} = App::MtAws::TreeHash->new();
	$self->SUPER::reinit(@_);
}

sub treehash { shift->{treehash} }

sub _flush
{
	my ($self) = @_;
	if ($self->{pending_length}) {
		open_file(my $fh, $self->{tempfile}, mode => '+<', binary => 1) or delayed_confess "cant open file $self->{tempfile} $!";
		flock $fh, LOCK_EX or delayed_confess;
		$fh->flush();
		$fh->autoflush(1);
		seek $fh, $self->{position}+$self->{incr_position}, SEEK_SET or delayed_confess "cannot seek() $!";
		$self->{incr_position} += $self->_flush_buffers($fh);
		close $fh or delayed_confess; # close will unlock
	}
}

sub finish
{
	my ($self) = @_;
	my @r = $self->SUPER::finish();
	return @r;
}


package App::MtAws::HttpFileWriter;

our $VERSION = '1.101';

use strict;
use warnings;
use utf8;
use App::MtAws::Utils;
use Carp;
use base qw/App::MtAws::HttpWriter/;


sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->SUPER::initialize();
	$self->initialize();
	return $self;
}

sub initialize
{
	my ($self) = @_;
	defined($self->{tempfile}) or confess;
}

sub reinit
{
	my $self = shift;
	undef $self->{fh};
	open_file($self->{fh}, $self->{tempfile}, mode => '+<', binary => 1) or confess "cant open file $self->{tempfile} $!";
	binmode $self->{fh};
	$self->{treehash} = App::MtAws::TreeHash->new();
	$self->SUPER::reinit(@_);
}

sub treehash { shift->{treehash} }

sub _flush
{
	my ($self) = @_;
	if ($self->{pending_length}) {
		$self->_flush_buffers($self->{fh});
	}
}

sub finish
{
	my ($self) = @_;
	my @r = $self->SUPER::finish();
	close $self->{fh} or confess;
	return @r;
}


package App::MtAws::HttpMemoryWriter;

our $VERSION = '1.101';

use strict;
use warnings;
use utf8;
use App::MtAws::Utils;
use Carp;
use base qw/App::MtAws::HttpWriter/;


sub new
{
	my ($class, %args) = @_;
	my $self = {};
	bless $self, $class;
	return $self;
}

sub reinit
{
	my $self = shift;
	$self->{size} = shift;
	$self->{buffer} = '';
	$self->{total_length} = 0;
}

sub add_data
{
	my $self = $_[0];
	return unless defined($_[1]);
	$self->{buffer} .= $_[1];
	$self->{total_length} += length($_[1]);
	1;
}

sub finish
{
	my ($self) = @_;
	return ($self->{total_length} && ($self->{total_length} == $self->{size})) ? ('ok') : ('retry', 'Unexpected end of data');
}

1;
