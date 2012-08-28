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

package LineProtocol;

use strict;
use warnings;

use JSON::XS;


require Exporter;
use base qw/Exporter/;

our @EXPORT = qw/encode_data decode_data/;
our @EXPORT_OK = qw/escape unescape/;

# yes, a module, so we can unit-test it (JSON and YAML have different serialization implementeation)
my $json_coder = JSON::XS->new->ascii->allow_nonref;

sub decode_data
{
  my ($yaml_e) = @_;
  return $json_coder->decode($yaml_e);
}

sub encode_data
{
  my ($data) = @_;
  return $json_coder->encode($data);
}


1;

__END__
