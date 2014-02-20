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

our $VERSION = '1.114';

use strict;
use warnings;
use utf8;

use Carp;

use App::MtAws::Glacier::Inventory ();
use base q{App::MtAws::Glacier::Inventory};

sub new
{
	my $class = shift;
	my $self = { rawdata => \$_[0] };
	bless $self, $class;
	$self;
}

sub _parse
{
	my ($self) = @_;

	# Text::CSV with below options does not seem to work for our case
	# ( { binary => 1 , allow_whitespace => 1, quote_char => '"', allow_loose_quotes => 1, escape_char => "\\", auto_diag=>1} )
	# because Amazon CSV is buggy https://forums.aws.amazon.com/thread.jspa?threadID=141807&tstart=0

	my $re = undef;
	my @fields;
	my @records;
	while (${$self->{rawdata}} =~ /^(.*?)\r?$/gsm) {
		my $line = $1;
		if(!defined $re) {
			@fields = split /,/, $line;
			for (@fields) {
				s/^\"//;
				s/\"$//;
			}
			my $re_s .= join(',', map {
				qr{
					(
						([^\\\"\,]*?)|
						(?:\"(
							(?:\\\"|\\|.)*)
						\")
					)
				}x;

			} 1..@fields);
			$re = qr/^$re_s$/;

		} else {
			my @x = $line =~ /$re/xm or confess "Bad CSV line [$line]";;
			my %data;
			@data{@fields} = map {
				if (defined $x[$_*3+2]) {
					my $s = $x[$_*3+2];
					$s =~ s/\\"/"/g;
					$s;
				} elsif (defined $x[$_*3+1]) {
					$x[$_*3+1];
				} else {
					confess;
				}
			} (0..$#fields);
			push @records, \%data;

		}
	}
	$self->{data} = { ArchiveList => \@records };
}

1;
