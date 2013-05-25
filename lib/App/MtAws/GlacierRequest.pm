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

package App::MtAws::GlacierRequest;

use strict;
use warnings;
use utf8;
use POSIX;
use LWP::UserAgent;
use HTTP::Request::Common;
use App::MtAws::TreeHash;
use Digest::SHA qw/hmac_sha256 hmac_sha256_hex sha256_hex sha256/;
use App::MtAws::MetaData;
use App::MtAws::Utils;
use App::MtAws::Exceptions;
use Carp;




sub new
{
	my ($class, $options) = @_;
	my $self = {};
	bless $self, $class;
	
	defined($self->{$_} = $options->{$_})||confess $_ for (qw/region key secret protocol/);
	defined($options->{$_}) and $self->{$_} = $options->{$_} for (qw/vault token/); # TODO: validate vault later
	
	
	confess unless $self->{protocol} =~ /^https?$/; # we check external data here, even if it's verified in the beginning, especially if it's used to construct URL
	$self->{service} ||= 'glacier';
	$self->{account_id} = '-';
	$self->{host} = "$self->{service}.$self->{region}.amazonaws.com";

	$self->{headers} = [];
   
	$self->add_header('Host', $self->{host});
	$self->add_header('x-amz-glacier-version', '2012-06-01') if $self->{service} eq 'glacier';
	$self->add_header('x-amz-security-token', $self->{token}) if defined $self->{token};
	
	return $self;                                                                                                                                                                                                                                                                     
}                      

sub add_header
{
	my ($self, $name, $value) = @_;
	push @{$self->{headers}}, { name => $name, value => $value};
}

sub create_multipart_upload
{
	my ($self, $partsize, $relfilename, $mtime) = @_;
	
	defined($relfilename)||confess;
	defined($mtime)||confess;
	$partsize||confess;
	
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/multipart-uploads";
	$self->{method} = 'POST';

	$self->add_header('x-amz-part-size', $partsize);
	
	# currently meat_encode only returns undef if filename is too big
	defined($self->{description} = App::MtAws::MetaData::meta_encode($relfilename, $mtime)) or
		die exception 'file_name_too_big' =>
		"Relative filename %string filename% is too big to store in Amazon Glacier metadata. ".
		"Limit is about 700 ASCII characters or 350 2-byte UTF-8 character.",
		filename => $relfilename;
	$self->add_header('x-amz-archive-description', $self->{description});
	
	my $resp = $self->perform_lwp();
	return $resp ? $resp->header('x-amz-multipart-upload-id') : undef;
}

sub upload_part
{
	my ($self, $uploadid, $dataref, $offset, $part_final_hash) = @_;
	
	$uploadid||confess;
	($self->{dataref} = $dataref)||confess;
	defined($offset)||confess;
	($self->{part_final_hash} = $part_final_hash)||confess;
	
	$self->_calc_data_hash;
   
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/multipart-uploads/$uploadid";
	$self->{method} = 'PUT';
	$self->add_header('Content-Type', 'application/octet-stream');
	$self->add_header('Content-Length', length(${$self->{dataref}}));
	$self->add_header('x-amz-content-sha256', $self->{data_sha256});
	$self->add_header('x-amz-sha256-tree-hash', $self->{part_final_hash});
	my ($start, $end) = ($offset, $offset+length(${$self->{dataref}})-1 );
	$self->add_header('Content-Range', "bytes ${start}-${end}/*");
	
	my $resp = $self->perform_lwp();
	return $resp ? 1 : undef;
}


sub finish_multipart_upload
{
	my ($self, $uploadid, $size, $treehash) = @_;

	$uploadid||confess;
	$size||confess;
	$treehash||confess;
   
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/multipart-uploads/$uploadid";
	$self->{method} = 'POST';
	$self->add_header('x-amz-sha256-tree-hash', $treehash);
	$self->add_header('x-amz-archive-size', $size);

	my $resp = $self->perform_lwp();
	return $resp ? $resp->header('x-amz-archive-id') : undef;
}


sub delete_archive
{
	my ($self, $archive_id) = @_;

	$archive_id||confess;
   
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/archives/$archive_id";
	$self->{method} = 'DELETE';
	
	my $resp = $self->perform_lwp();
	return $resp ? 1 : undef;
}


sub retrieve_archive
{
	my ($self, $archive_id) = @_;
	
	$archive_id||confess;
   
	$self->add_header('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs";
	$self->{method} = 'POST';

	#  add "SNSTopic": "sometopic"
	my $body = <<"END";
{
  "Type": "archive-retrieval",
  "ArchiveId": "$archive_id"
}
END

	$self->{dataref} = \$body;
	
	my $resp = $self->perform_lwp();
	return $resp ? $resp->header('x-amz-job-id') : undef;
}

sub retrieve_inventory
{
	my ($self) = @_;
	
	$self->add_header('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs";
	$self->{method} = 'POST';

	#  add "SNSTopic": "sometopic"
	my $body = <<"END";
{
  "Type": "inventory-retrieval",
  "Format": "JSON"
}
END

	$self->{dataref} = \$body;
	
	my $resp = $self->perform_lwp();
	return $resp ? $resp->header('x-amz-job-id') : undef;
}

sub retrieval_fetch_job
{
	my ($self, $marker) = @_;
	
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs";

	$self->{params} = { completed => 'true' };
	$self->{params}->{marker} = $marker if defined($marker);
	
	$self->{method} = 'GET';

	my $resp = $self->perform_lwp();
	return $resp->decoded_content; # TODO: return reference?
}


# TODO: rename
sub retrieval_download_job
{
	my ($self, $jobid, $filename) = @_;

	$jobid||confess;
	defined($filename)||confess;
   
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs/$jobid/output";
	$self->{content_file} = binaryfilename $filename; # TODO: use temp filename for transactional behaviour
	$self->{method} = 'GET';

	my $resp = $self->perform_lwp();
	return $resp ? 1 : undef; # $resp->decoded_content is undefined here as content_file used
}


sub retrieval_download_to_memory
{
	my ($self, $jobid) = @_;

	$jobid||confess;
   
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs/$jobid/output";
	$self->{method} = 'GET';

	my $resp = $self->perform_lwp();
	
	if ($ENV{MTGLACIER_DEBUG_INVENTORY}) {
		my $d_content = $resp->decoded_content;
		my $content = $resp->content;
		
		open FF, ">_download_inventory_headers.log";
		print FF $resp->request->dump;
		print FF $resp->dump;
		print FF "\n\nContent length:[".length($d_content)."]\n";
		print FF "Content match decoded content:[".($d_content eq $content)."]\n";
		close FF;

		open FF, ">_download_inventory_body.log";
		print FF $d_content;
		close FF;
	}

	if ($resp) {
		my $r = $resp->decoded_content; # decoded_content is NOT binary string because MIME type is not text/*
		confess if is_wide_string($r);
		return $r;
	} else {
		return undef;
	}
}

# TODO: remove
sub download_inventory
{
	my ($self, $jobid) = @_;

	$jobid||confess;
   
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs/$jobid/output";
	$self->{method} = 'GET';

	my $resp = $self->perform_lwp();
	return $resp ? $resp : undef; # $resp->decoded_content is undefined here as content_file used
}


sub create_vault
{
	my ($self, $vault_name) = @_;

	confess unless defined($vault_name);
   
	$self->{url} = "/$self->{account_id}/vaults/$vault_name";
	$self->{method} = 'PUT';

	my $resp = $self->perform_lwp();
	return $resp ? $resp->header('x-amzn-RequestId') : undef;
}

sub delete_vault
{
	my ($self, $vault_name) = @_;

	confess unless defined($vault_name);
   
	$self->{url} = "/$self->{account_id}/vaults/$vault_name";
	$self->{method} = 'DELETE';

	my $resp = $self->perform_lwp();
	return $resp ? $resp->header('x-amzn-RequestId') : undef;
}



sub _calc_data_hash
{
	my ($self) = @_;

	if (length(${$self->{dataref}}) <= 1048576) {
		$self->{data_sha256} = $self->{part_final_hash};
	} else {
		$self->{data_sha256} = sha256_hex(${$self->{dataref}});
	}
}


sub _sign
{
	my ($self) = @_;
	
	my $now = time();
	
	$self->{last_request_time} = $now;
	
	my $date8601 = strftime("%Y%m%dT%H%M%SZ", gmtime($now)); # TODO: use same timestamp when writing to journal
	my $datestr = strftime("%Y%m%d", gmtime($now));
	 
	
	$self->{req_headers} = [
		{ name => 'x-amz-date', value => $date8601 },
	];
	
	
	# getting canonical URL
	
	my @all_headers = sort { $a->{name} cmp $b->{name} } (@{$self->{headers}}, @{$self->{req_headers}});
	
	
	my $canonical_headers = join ("\n", map { lc($_->{name}).":".trim($_->{value}) } @all_headers);
	my $signed_headers = join (';', map { lc($_->{name}) } @all_headers);
	
	my $bodyhash = $self->{data_sha256} ?
		$self->{data_sha256} :
		( $self->{dataref} ? sha256_hex(${$self->{dataref}}) : sha256_hex('') );
	
	$self->{params_s} = $self->{params} ? join ('&', map { "$_=$self->{params}->{$_}" } sort keys %{$self->{params}}) : ""; # TODO: proper URI encode
	my $canonical_query_string = $self->{params_s};
	
	my $canonical_url = join("\n", $self->{method}, $self->{url}, $canonical_query_string, $canonical_headers, "", $signed_headers, $bodyhash);
	my $canonical_url_hash = sha256_hex($canonical_url);

	
	# /getting canonical URL
	
	my $credentials = "$datestr/$self->{region}/$self->{service}/aws4_request";

	my $string_to_sign = join("\n", "AWS4-HMAC-SHA256", $date8601, $credentials, $canonical_url_hash);

	my ($kSigning, $kSigning_hex) = get_signature_key($self->{secret}, $datestr, $self->{region}, $self->{service});
	my $signature = hmac_sha256_hex($string_to_sign, $kSigning);
	
	
	
	my $auth = "AWS4-HMAC-SHA256 Credential=$self->{key}/$credentials, SignedHeaders=$signed_headers, Signature=$signature";

	push @{$self->{req_headers}}, { name => 'Authorization', value => $auth};
}


sub perform_lwp
{
	my ($self) = @_;
	
	for my $i (1..100) {
		$self->_sign();

		my $ua = LWP::UserAgent->new(timeout => 120);
		$ua->protocols_allowed ( [ 'https' ] ) if $self->{protocol} eq 'https'; # Lets hard code this.
		$ua->agent("mt-aws-glacier/$App::MtAws::VERSION (http://mt-aws.com/) "); 
		my $req = undef;
		my $url = $self->{protocol} ."://$self->{host}$self->{url}";
		$url = $self->{protocol} ."://$ENV{MTGLACIER_FAKE_HOST}$self->{url}" if $ENV{MTGLACIER_FAKE_HOST};
		if ($self->{protocol} eq 'https') {
			if ($ENV{MTGLACIER_FAKE_HOST}) {
				$ua->ssl_opts( verify_hostname => 0, SSL_verify_mode=>0); #Hostname mismatch causes LWP to error.
			} else {
				$ua->ssl_opts( verify_hostname => 1, SSL_verify_mode=>1);
			}
		}
		$url .= "?$self->{params_s}" if $self->{params_s};
		if ($self->{method} eq 'PUT') {
			$req = HTTP::Request::Common::PUT( $url, Content=>$self->{dataref});
		} elsif ($self->{method} eq 'POST') {
			if ($self->{dataref}) {
				$req = HTTP::Request::Common::POST( $url, Content_Type => 'form-data', Content=>${$self->{dataref}});
			} else {
				$req = HTTP::Request::Common::POST( $url );
			}
		} elsif ($self->{method} eq 'DELETE') {
			$req = HTTP::Request::Common::DELETE( $url);
		} elsif ($self->{method} eq 'GET') {
			$req = HTTP::Request::Common::GET( $url);
		} else {
			confess;
		}
		for ( @{$self->{headers}}, @{$self->{req_headers}} ) {
			$req->header( $_->{name}, $_->{value} );
		}
		my $resp = undef;

		my $t0 = time();
		if ($self->{content_file}) {
			$resp = $ua->request($req, $self->{content_file});
		} else {
			$resp = $ua->request($req);
		}
		my $dt = time()-$t0;

		if ($resp->code =~ /^(500|408)$/) {
			print "PID $$ HTTP ".$resp->code." This might be normal. Will retry ($dt seconds spent for request)\n";
			throttle($i);
		} elsif (defined($resp->header('X-Died')) && length($resp->header('X-Died')) && $resp->header('X-Died') =~ /^read timeout/i) {
			print "PID $$ HTTP Timeout. Will retry ($dt seconds spent for request)\n";
			throttle($i);
		} elsif ($resp->code =~ /^2\d\d$/) {
			return $resp;
		} else {
			print STDERR "Error:\n";
			print STDERR $req->dump;
			print STDERR $resp->dump;
			print STDERR "\n";
			return undef;
		}
	}
	return undef;
}

sub throttle
{
	my ($i) = @_;
	if ($i <= 5) {
		sleep 1;
	} elsif ($i <= 10) {
		sleep 5;
	} elsif ($i <= 20) {
		sleep 15;
	} elsif ($i <= 50) {
		sleep 60
	} else {
		sleep 180;
	}
}


sub get_signature_key
{
	my ($secret, $date, $region, $service) = @_;
	my $kSecret = $secret;
	my $kDate = hmac_sha256($date, "AWS4".$kSecret);
	my $kRegion = hmac_sha256($region, $kDate);
	my $kService = hmac_sha256($service, $kRegion);
	my $kSigning = hmac_sha256("aws4_request", $kService);
	my $kSigning_hex = hmac_sha256_hex($kService, "aws4_request");

	return ($kSigning, $kSigning_hex);
}

sub trim
{
	my ($s) = @_;
	$s =~ s/\s*\Z//gsi;
	$s =~ s/\A\s*//gsi;
	$s;
}


1;
