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

package GlacierRequest;

use strict;
use warnings;
use utf8;
use POSIX;
use LWP::UserAgent;
use HTTP::Request::Common;
use TreeHash;
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex sha256);

require Exporter;
use base qw/Exporter/;

our @EXPORT_OK = qw/get_signature_key/;

sub add_header
{
	my ($self, $name, $value) = @_;
    push @{$self->{headers}}, { name => $name, value => $value};
}



sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{secret} || die;
    $self->{key} || die;
    $self->{region}||die;
    $self->{service} ||= 'glacier';
    $self->{account_id} = '-';
    $self->{host} = "$self->{service}.$self->{region}.amazonaws.com";

    $self->{headers} = [];
   
    $self->add_header('Host', $self->{host});
    $self->add_header('x-amz-glacier-version', '2012-06-01') if $self->{service} eq 'glacier';
    
    return $self;                                                                                                                                                                                                                                                                     
}                      

sub init_create_multipart_upload
{
    my ($self, %args) = @_;
    
    $self->{vault} = $args{vault} || die;
    $self->{partsize} = $args{partsize} || die;
   
    $self->{url} = "/$self->{account_id}/vaults/$self->{vault}/multipart-uploads";
    $self->{method} = 'POST';

	$self->add_header('x-amz-part-size', $self->{partsize});
	$self->add_header('x-amz-archive-description', 'mtglacier archive');
	
}

sub init_delete_archive
{
    my ($self, %args) = @_;
    
    $self->{vault} = $args{vault} || die;
    $self->{archive_id} = $args{archive_id} || die;
   
    $self->{url} = "/$self->{account_id}/vaults/$self->{vault}/archives/$self->{archive_id}";
    $self->{method} = 'DELETE';
}

sub init_retrieve_archive
{
    my ($self, %args) = @_;
    
    $self->{vault} = $args{vault} || die;
    $self->{archive_id} = $args{archive_id} || die;
   
	$self->add_header('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');
    $self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs";
    $self->{method} = 'POST';

    my $body = <<"END";
{
  "Type": "archive-retrieval",
  "ArchiveId": "$self->{archive_id}"
}
END

	#  add "SNSTopic": "sometopic"
    $self->{dataref} = \$body;
}

sub init_retrieval_fetch_job
{
    my ($self, %args) = @_;
    
    $self->{vault} = $args{vault} || die;
   
    $self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs";

    $self->{params} = { completed => 'true' };
    $self->{params}->{marker} = $args{marker} if $args{marker};
    
    $self->{method} = 'GET';
}

sub init_retrieval_download_job
{
    my ($self, %args) = @_;
    
    $self->{vault} = $args{vault} || die;
    $self->{jobid} = $args{jobid} || die;
    $self->{filename} = $args{filename} || die; # this is absolute filename, so it can't start with "0"
   
    $self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs/$self->{jobid}/output";
    $self->{content_file} = $self->{filename};
    $self->{method} = 'GET';
}

sub init_finish_multipart_upload
{
    my ($self, %args) = @_;
    
    $self->{vault} = $args{vault} || die;
    $self->{uploadid} = $args{uploadid} || die;
   
    $self->{url} = "/$self->{account_id}/vaults/$self->{vault}/multipart-uploads/$self->{uploadid}";
    $self->{method} = 'POST';
	$self->add_header('x-amz-sha256-tree-hash', $args{treehash});
	$self->add_header('x-amz-archive-size', $args{size});
	undef $self->{dataref};	
}

sub init_upload_multipart_part
{
    my ($self, %args) = @_;
    
    $self->{vault} = $args{vault} || die;
    $self->{dataref} = $args{dataref} || die;
    die unless defined($args{offset});
    $self->{offset} = $args{offset};
    $self->{part_final_hash}=$args{part_final_hash};
    die unless defined($self->{part_final_hash});
    $self->{uploadid} = $args{uploadid} || die;
    
    $self->_calc_data_hash;
   
    $self->{url} = "/$self->{account_id}/vaults/$self->{vault}/multipart-uploads/$self->{uploadid}";
    $self->{method} = 'PUT';
	$self->add_header('Content-Type', 'application/octet-stream');
	$self->add_header('Content-Length', length(${$self->{dataref}}));
	$self->add_header('x-amz-content-sha256', $self->{data_sha256});
	$self->add_header('x-amz-sha256-tree-hash', $self->{part_final_hash});
	 my ($start, $end) = ($self->{offset}, $self->{offset}+length(${$self->{dataref}})-1 );
	$self->add_header('Content-Range', "bytes ${start}-${end}/*");
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
    
	my $date8601 = strftime("%Y%m%dT%H%M%SZ", gmtime($now));
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
	
	my $canonical_url = "$self->{method}\n$self->{url}\n$canonical_query_string\n$canonical_headers\n\n$signed_headers\n$bodyhash";
	my $canonical_url_hash = sha256_hex($canonical_url);
	
	# /getting canonical URL
	
	my $credentials = "$datestr/$self->{region}/$self->{service}/aws4_request";

	my $string_to_sign = "AWS4-HMAC-SHA256\n$date8601\n$credentials\n$canonical_url_hash";

	my ($kSigning, $kSigning_hex) = get_signature_key($self->{secret}, $datestr, $self->{region}, $self->{service});
	my $signature = hmac_hex($kSigning, $string_to_sign);
	
	my $auth = "AWS4-HMAC-SHA256 Credential=$self->{key}/$credentials, SignedHeaders=$signed_headers, Signature=$signature";

	push @{$self->{req_headers}}, { name => 'Authorization', value => $auth};
}

sub upload_archive
{
	my ($class, $region, $key, $secret, $vault, $dataref) = @_;
	my $req = $class->new(region => $region, key => $key, secret => $secret);
	$req->init_upload_archive(vault => $vault, dataref => $dataref);
	my $resp = $req->perform_lwp();
	return $resp ? $resp->header('X-Amz-Archive-Id') : undef;
}

sub create_multipart_upload
{
	my ($class, $region, $key, $secret, $vault, $size) = @_;
	my $req = $class->new(region => $region, key => $key, secret => $secret);
	$req->init_create_multipart_upload(vault => $vault, partsize => $size);
	my $resp = $req->perform_lwp();
	return $resp ? $resp->header('X-Amz-Multipart-Upload-Id') : $resp; # TODO: lowercase source headers!
}

sub delete_archive
{
	my ($class, $region, $key, $secret, $vault, $archive_id) = @_;
	my $req = $class->new(region => $region, key => $key, secret => $secret);
	$req->init_delete_archive(vault => $vault, archive_id => $archive_id);
	my $resp = $req->perform_lwp();
	return $resp;
}

sub retrieve_archive
{
	my ($class, $region, $key, $secret, $vault, $archive_id) = @_;
	my $req = $class->new(region => $region, key => $key, secret => $secret);
	$req->init_retrieve_archive(vault => $vault, archive_id => $archive_id);
	my $resp = $req->perform_lwp();
	return $resp;
}
sub retrieval_fetch_job
{
	my ($class, $region, $key, $secret, $vault, $marker) = @_;
	my $req = $class->new(region => $region, key => $key, secret => $secret);
	$req->init_retrieval_fetch_job(vault => $vault, marker=> $marker);
	my $resp = $req->perform_lwp();
	return $resp->decoded_content;
}

sub retrieval_download_job
{
	my ($class, $region, $key, $secret, $vault, $jobid, $filename) = @_;
	my $req = $class->new(region => $region, key => $key, secret => $secret);
	$req->init_retrieval_download_job(vault => $vault, jobid => $jobid, filename => $filename);
	my $resp = $req->perform_lwp();
	return $resp->decoded_content;
}

sub upload_part
{
	my ($class, $region, $key, $secret, $vault, $uploadid, $dataref, $offset, $part_final_hash) = @_;
	my $req = $class->new(region => $region, key => $key, secret => $secret);
	
	$req->init_upload_multipart_part(vault => $vault, dataref=>$dataref, offset=>$offset, uploadid=>$uploadid, part_final_hash => $part_final_hash);
	my $resp = $req->perform_lwp();
	return $resp;
}

sub finish_multipart_upload
{
	my ($class, $region, $key, $secret, $vault, $uploadid, $size, $treehash) = @_;
	my $req = $class->new(region => $region, key => $key, secret => $secret);
	$req->init_finish_multipart_upload(vault => $vault, uploadid=>$uploadid, size => $size, treehash => $treehash);
	my $resp = $req->perform_lwp();
	return $resp->header('X-Amz-Archive-Id');
}


sub perform_lwp
{
	my ($self) = @_;
	
	for my $i (1..100) {
		$self->_sign();	
		
		my $ua = LWP::UserAgent->new(timeout => 120);
		$ua->agent("mt-aws-glacier/$main::VERSION (http://mt-aws.com/) "); 
	    my $req = undef;
	    my $url = "http://$self->{host}$self->{url}";
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
			die;
		}
		
	    for ( @{$self->{headers}}, @{$self->{req_headers}} ) {
	    	$req->header( $_->{name}, $_->{value} );
	    }

		my $resp = undef;
		if ($self->{content_file}) {
	    	$resp = $ua->request($req, $self->{content_file});
		} else {
	    	$resp = $ua->request($req);
		}

		if ($resp->code =~ /^(500|408)$/) {
			print "PID $$ HTTP ".$resp->code." This might be normal. Will retry\n";
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
		} elsif ($resp->code =~ /^2\d\d$/) {
			return $resp;
		} else {
			print "Error:\n";
		  	print $req->dump;
		    print $resp->dump;
		    print "\n";
			return undef;
		}
	}
	return undef;
}

sub snd
{
	my ($socket, $str) = @_;
#	print ">>> $str";
	syswrite $socket, $str;
}


sub get_signature_key
{
	my ($secret, $date, $region, $service) = @_;
	my $kSecret = $secret;
	my $kDate = hmac("AWS4".$kSecret, $date);
	my $kRegion = hmac($kDate, $region);
	my $kService = hmac($kRegion, $service);
	my $kSigning = hmac($kService, "aws4_request");
	my $kSigning_hex = hmac_sha256_hex("aws4_request", $kService);

	return ($kSigning, $kSigning_hex);
}

sub hmac
{
	my ($key, $msg) = @_;
	hmac_sha256($msg, $key);
}

sub hmac_hex
{
	my ($key, $msg) = @_;
	my $h =	hmac_sha256_hex($msg, $key);
	return $h;
}

sub trim
{
	my ($s) = @_;
	$s =~ s/\s*\Z//gsi;
	$s =~ s/\A\s*//gsi;
	$s;
}


1;
