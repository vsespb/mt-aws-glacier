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

package App::MtAws::Glacier::Inventory::CSV;

our $VERSION = '1.112';

use strict;
use warnings;
use utf8;

use Carp;

use App::MtAws::Glacier::Inventory ();
use base q{App::MtAws::Glacier::Inventory};

our %field_re = (
	ArchiveId => '[A-Za-z0-9_-]+',
	ArchiveDescription => '.*?',
	CreationDate => '[^,]+?',
	Size => '[^,]+?',
	SHA256TreeHash => '[^,]+?',
);

sub new
{
	my $class = shift;
	my $self = { rawdata => \$_[0] };
	bless $self, $class;
	$self;
}

sub _unescape
{
	return unless $_[0] =~ /^\"/;
	$_[0] =~ s/^\"//;
	$_[0] =~ s/\"$//;
	$_[0] =~ s/\\"/"/g;
}


sub _parse
{
	my ($self) = @_;

	# Text::CSV with belo options does not seem to work for our case
	# ( { binary => 1 , allow_whitespace => 1, quote_char => '"', allow_loose_quotes => 1, escape_char => "\\", auto_diag=>1} )
	# because Amazon CSV is buggy https://forums.aws.amazon.com/thread.jspa?threadID=141807&tstart=0

	my $re = undef;
	my @fields;
	my @records;
	while (${$self->{rawdata}} =~ /^(.*?)\r?$/gsm) {
		my $line = $1;
		if(!defined $re) {
			@fields = split /\s*,\s*/, $line;
			confess "Bad CSV header [$line]" unless
				join(',', sort @fields) eq
				join(',', sort qw/ArchiveId ArchiveDescription CreationDate Size SHA256TreeHash/);
			_unescape($_) for (@fields);
			my $re_str = join(',', map { "\\s*($_)\\s*" } map { $field_re{$_} or confess } @fields);
			$re = qr/^$re_str$/;
		} else {
			my %data;
			@data{@fields} = $line =~ $re or confess "Bad CSV line [$line]";
			_unescape($data{$_}) for (@fields);
			push @records, \%data;
		}
	}
	$self->{data} = { ArchiveList => \@records };
}

1;
