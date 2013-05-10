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

package App::MtAws::LineProtocol;

use strict;
use warnings;
use utf8;
use Carp;

use JSON::XS;
use App::MtAws::Utils;

require Exporter;
use base qw/Exporter/;

our @EXPORT = qw/ get_data send_data/;
our @EXPORT_OK = qw/escape unescape encode_data decode_data/;

# yes, a module, so we can unit-test it (JSON and YAML have different serialization implementeation)
my $json_coder = JSON::XS->new->utf8(1)->ascii(1)->allow_nonref;

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


sub get_data
{
	my ($fh) = @_;
	
	my ($len, $line);

	sysreadfull($fh, $len, 8) &&
	sysreadfull($fh, $line, $len+0) or
	return;
	
	chomp $line;
	my ($pid, $action, $taskid, $attachmentsize, $data_e) = split /\t/, $line;
	my $attachment = undef;
	if ($attachmentsize) {
		sysreadfull($fh, $attachment, $attachmentsize) or
			return;
	}
	my $data = decode_data($data_e);
	return ($pid, $action, $taskid, $data, $attachment ? \$attachment : ());
}

sub send_data
{
	my ($fh, $action, $taskid, $data, $attachmentref) = @_;
	my $data_e = encode_data($data);
	confess "Attachment should be a binary string" if $attachmentref && is_wide_string($$attachmentref);
	my $attachmentsize = $attachmentref ? length($$attachmentref) : 0;
	my $line = "$$\t$action\t$taskid\t$attachmentsize\t".$data_e."\n"; # encode_data returns ASCII-7bit data, so ok here
	confess if is_wide_string($line);
	syswritefull($fh, sprintf("%08d", length($line))) &&
	syswritefull($fh, $line) &&
		(!$attachmentsize || syswritefull($fh, $$attachmentref)) or
		return;
	return 1;
}



1;

__END__
