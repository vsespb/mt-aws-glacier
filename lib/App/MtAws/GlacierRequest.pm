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

package App::MtAws::GlacierRequest;

our $VERSION = '1.120';

use strict;
use warnings;
use utf8;
use POSIX;
use LWP 5.803;
use LWP::UserAgent;
use URI::Escape;
use HTTP::Request;
use Digest::SHA qw/hmac_sha256 hmac_sha256_hex sha256_hex/;
use App::MtAws::MetaData;
use App::MtAws::Utils;
use App::MtAws::Exceptions;
use App::MtAws::HttpSegmentWriter;
use App::MtAws::SHAHash qw/large_sha256_hex/;
use Carp;

sub new
{
	my ($class, $options) = @_;
	my $self = {};
	bless $self, $class;

	defined($self->{$_} = $options->{$_})||confess $_ for (qw/region key secret protocol timeout/);
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
		"Either relative filename %string filename% is too big to store in Amazon Glacier metadata. ".
		"(Limit is about 700 ASCII characters or 350 2-byte UTF-8 characters) or file modification time %string mtime% out of range".
		"(Only years from 1000 to 9999 are supported)",
		filename => $relfilename, mtime => $mtime; # TODO: more clear error
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
	# no Test::Tabs
	my $body = <<"END";
{
  "Type": "archive-retrieval",
  "ArchiveId": "$archive_id"
}
END

	# use Test::Tabs
	$self->{dataref} = \$body;

	my $resp = $self->perform_lwp();
	return $resp ? $resp->header('x-amz-job-id') : undef;
}

sub retrieve_inventory
{
	my ($self, $format) = @_;

	$format or confess;

	if ($format eq 'json') {
		$format = 'JSON';
	} elsif ($format eq 'csv') {
		$format = 'CSV';
	} else {
		confess "unknown inventory format $format";
	}

	$self->add_header('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');
	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs";
	$self->{method} = 'POST';

	my $job_meta = App::MtAws::MetaData::meta_job_encode(META_JOB_TYPE_FULL);

	#  add "SNSTopic": "sometopic"
	# no Test::Tabs
	my $body = <<"END";
{
  "Type": "inventory-retrieval",
  "Description": "$job_meta",
  "Format": "$format"
}
END
	# use Test::Tabs
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
	my ($self, $jobid, $relfilename, $tempfile, $size, $journal_treehash) = @_;

	$journal_treehash||confess;
	$jobid||confess;
	defined($tempfile)||confess;
	defined($relfilename)||confess;
	$size or confess "no size";

	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs/$jobid/output";

	$self->{expected_size} = $size;
	$self->{writer} = App::MtAws::HttpFileWriter->new(tempfile => $tempfile);

	$self->{method} = 'GET';

	my $resp = $self->perform_lwp();
	my $reported_th = $resp->header('x-amz-sha256-tree-hash') or confess;

	$self->{writer}->treehash->calc_tree();
	my $th = $self->{writer}->treehash->get_final_hash();

	$reported_th eq $th or
		die exception 'treehash_mismatch_full' =>
		'TreeHash for received file %string filename% (full file) does not match. '.
		'TreeHash reported by server: %reported%, Calculated TreeHash: %calculated%, TreeHash from Journal: %journal_treehash%',
		calculated => $th, reported => $reported_th, journal_treehash => $journal_treehash, filename => $relfilename;

	$reported_th eq $journal_treehash or
		die exception 'treehash_mismatch_journal' =>
		'TreeHash for received file %string filename% (full file) does not match TreeHash in journal. '.
		'TreeHash reported by server: %reported%, Calculated TreeHash: %calculated%, TreeHash from Journal: %journal_treehash%',
		calculated => $th, reported => $reported_th, journal_treehash => $journal_treehash, filename => $relfilename;

	return $resp ? 1 : undef;
}

sub segment_download_job
{
	my ($self, $jobid, $tempfile, $filename, $position, $size) = @_;

	$jobid||confess;
	defined($position) or confess "no position";
	$size or confess "no size";
	defined($filename)||confess;

	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs/$jobid/output";

	$self->{expected_size} = $size;
	$self->{writer} = App::MtAws::HttpSegmentWriter->new(tempfile => $tempfile, position => $position, filename => $filename);

	$self->{method} = 'GET';
	my $end_position = $position + $size - 1;
	$self->add_header('Range', "bytes=$position-$end_position");

	my $resp = $self->perform_lwp();
	$resp && $resp->code == 206 or confess;

	my $reported_th = $resp->header('x-amz-sha256-tree-hash') or confess;
	$self->{writer}->treehash->calc_tree();
	my $th = $self->{writer}->treehash->get_final_hash();

	$reported_th eq $th or
		die exception 'treehash_mismatch_segment' =>
		'TreeHash for received segment of file %string filename% (position %position%, size %size%) does not match. '.
		'TreeHash reported by server %reported%, Calculated TreeHash %calculated%',
		calculated => $th, reported => $reported_th, filename => $filename, position => $position, size => $size;
		# TODO: better report relative filename

	my ($start, $end, $len) = $resp->header('Content-Range') =~ m!bytes\s+(\d+)\-(\d+)\/(\d+)!;

	confess unless defined($start) && defined($end) && $len;
	confess unless $end >= $start;
	confess unless $position == $start;
	confess unless $end_position == $end;

	return $resp ? 1 : undef; # $resp->decoded_content is undefined here as content_file used
}

sub retrieval_download_to_memory
{
	my ($self, $jobid) = @_;

	$jobid||confess;

	$self->{url} = "/$self->{account_id}/vaults/$self->{vault}/jobs/$jobid/output";
	$self->{method} = 'GET';

	my $resp = $self->perform_lwp();

	$resp or confess;

	my $itype = do {
		my $ct = $resp->content_type;
		if ($ct eq 'text/csv') {
			INVENTORY_TYPE_CSV
		} elsif ($ct eq 'application/json') {
			INVENTORY_TYPE_JSON
		} else {
			confess "Unknown mime-type $ct";
		}
	};
	return ($resp->content, $itype);
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

sub list_vaults
{
	my ($self, $marker) = @_;

	$self->{url} = "/$self->{account_id}/vaults";
	$self->{params}->{marker} = $marker if defined($marker);
	$self->{method} = 'GET';

	my $resp = $self->perform_lwp();
	return $resp->decoded_content; # TODO: return reference?
}


sub _calc_data_hash
{
	my ($self) = @_;

	if (length(${$self->{dataref}}) <= 1048576) {
		$self->{data_sha256} = $self->{part_final_hash};
	} else {
		$self->{data_sha256} = large_sha256_hex(${$self->{dataref}});
	}
}


sub _sign
{
	my ($self) = @_;

	my $now = time();

	$self->{last_request_time} = $now;  # we use same timestamp when writing to journal

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
		( $self->{dataref} ? large_sha256_hex(${$self->{dataref}}) : sha256_hex('') );

	$self->{params_s} = $self->{params} ? join ('&', map { "$_=".uri_escape($self->{params}->{$_}) } sort keys %{$self->{params}}) : "";
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


sub _max_retries { 100 }
sub _sleep($) { sleep shift }

sub throttle
{
	my ($i) = @_;
	if ($i <= 5) {
		_sleep 1;
	} elsif ($i <= 10) {
		_sleep 5;
	} elsif ($i <= 20) {
		_sleep 15;
	} elsif ($i <= 50) {
		_sleep 60
	} else {
		_sleep 180;
	}
}

sub perform_lwp
{
	my ($self) = @_;

	for my $i (1.._max_retries) {
		undef $self->{last_retry_reason};
		$self->_sign();

		my $ua = LWP::UserAgent->new(timeout => $self->{timeout});
		$ua->protocols_allowed ( [ 'https' ] ) if $self->{protocol} eq 'https'; # Lets hard code this.
		$ua->agent("mt-aws-glacier/${App::MtAws::VERSION} (http://mt-aws.com/) "); # use of App::MtAws::VERSION_MATURITY produce warning
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
			$req = HTTP::Request->new(PUT => $url, undef, $self->{dataref});
		} elsif ($self->{method} eq 'POST') {
			if ($self->{dataref}) {
				$req = HTTP::Request->new(POST => $url, [Content_Type => 'form-data'], ${$self->{dataref}});
			} else {
				$req = HTTP::Request->new(POST => $url );
			}
		} elsif ($self->{method} eq 'DELETE') {
			$req = HTTP::Request->new(DELETE => $url);
		} elsif ($self->{method} eq 'GET') {
			$req = HTTP::Request->new(GET => $url);
		} else {
			confess;
		}
		for ( @{$self->{headers}}, @{$self->{req_headers}} ) {
			$req->header( $_->{name}, $_->{value} );
		}
		my $resp = undef;

		my $t0 = time();
		if ($self->{content_file} && $self->{writer}) {
			confess "content_file and writer at same time";
		} elsif ($self->{content_file}) {
			$resp = $ua->request($req, $self->{content_file});
		} elsif ($self->{writer}) {
			my $size = undef;
			$resp = $ua->request($req, sub {
				unless (defined($size)) {
					if ($_[1] && $_[1]->isa('HTTP::Response')) {
						$size = $_[1]->content_length;
						if (!$size || ($self->{expected_size} && $size != $self->{expected_size})) {
							die exception
								wrong_file_size_in_journal =>
									'Wrong Content-Length received from server, probably wrong file size in Journal or wrong server';
						}
						$self->{writer}->reinit($size);
					} else {
						# we should "confess" here, but we cant, only exceptions propogated
						die exception "unknow_error" => "Unknown error, probably LWP version is too old";
					}
				}
				$self->{writer}->add_data($_[0]);
				1;
			});
		} else {
			$resp = $ua->request($req);
		}
		my $dt = time()-$t0;

		if (($resp->code eq '500') && $resp->header('Client-Warning') && ($resp->header('Client-Warning') eq 'Internal response')) {
			if ($resp->content =~ /Can't verify SSL peers without knowing which Certificate Authorities to trust/i) {
				die exception 'lwp_ssl_ca_exception' =>
					'Can\'t verify SSL peers without knowing which Certificate Authorities to trust. Probably "Mozilla::CA" module is missing';
			} else {
				print "PID $$ HTTP connection problem (timeout?). Will retry ($dt seconds spent for request)\n";
				$self->{last_retry_reason} = 'Internal response';
				throttle($i);
			}
		} elsif ($resp->code =~ /^(500|408)$/) {
			print "PID $$ HTTP ".$resp->code." This might be normal. Will retry ($dt seconds spent for request)\n";
			$self->{last_retry_reason} = $resp->code;
			throttle($i);
		} elsif (defined($resp->header('X-Died')) && (get_exception($resp->header('X-Died')))) {
			die $resp->header('X-Died'); # propogate our own exceptions
		} elsif (defined($resp->header('X-Died')) && length($resp->header('X-Died'))) {
			print "PID $$ HTTP connection problem. Will retry ($dt seconds spent for request)\n";
			$self->{last_retry_reason} = 'X-Died';
			throttle($i);
		} elsif ($resp->code =~ /^2\d\d$/) {
			if ($self->{writer}) {
				my ($c, $reason) = $self->{writer}->finish();
				if ($c eq 'retry') {
					print "PID $$ HTTP $reason. Will retry ($dt seconds spent for request)\n";
					$self->{last_retry_reason} = $reason;
					throttle($i);
				} elsif ($c ne 'ok') {
					confess;
				} else {
					return $resp;
				}
			} elsif (defined($resp->content_length) && $resp->content_length != length($resp->content)){
				print "PID $$ HTTP Unexpected end of data. Will retry ($dt seconds spent for request)\n";
				$self->{last_retry_reason}='Unexpected end of data';
				throttle($i);
			} else {
				return $resp;
			}
		} else {
			if ($resp->code =~ /^40[03]$/) {
				if ($resp->content_type && $resp->content_type eq 'application/json') {
					my $json = JSON::XS->new->allow_nonref;
					my $scalar = eval { $json->decode( $resp->content ); }; # we assume content always in utf8
					if (defined $scalar) {
						my $code = $scalar->{code};
						my $type = $scalar->{type};
						my $message = $scalar->{message};
						if ($code eq 'ThrottlingException') {
							print "PID $$ ThrottlingException. Will retry ($dt seconds spent for request)\n";
							$self->{last_retry_reason} = 'ThrottlingException';
							throttle($i);
							next;
						}
					}
				}
			}
			print STDERR "Error:\n";
			print STDERR dump_request_response($req, $resp);
			die exception 'http_unexpected_reply' => 'Unexpected reply from remote server';
		}
	}
	die exception 'too_many_tries' => "Request was not successful after "._max_retries." retries";
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
__END__
