package LineProtocol;

use strict;
use warnings;
use Error;

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
