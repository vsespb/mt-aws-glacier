#!/usr/bin/perl


use warnings;
use strict;
use HTTP::Daemon;
use Carp;
use File::Path;
use Data::Dumper;
use JSON::XS;
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex sha256);
use 5.010;

my $children_count = 1;
my $daemon = HTTP::Daemon->new(LocalHost => '127.0.0.1',	LocalPort => 9901, ReuseAddr => 1) || die;
my $json_coder = JSON::XS->new->utf8->allow_nonref;

my $config = { key=>'AKIAJ2QN54K3SOFABCDE', secret => 'jhuYh6d73hdhGndk1jdHJHdjHghDjDkkdkKDkdkd'};

$ARGV[0]||die "Specify temporary folder";

for my $n (1..$children_count) {
	if (!fork()) {
		while (my $conn = $daemon->accept) {
			my $request = $conn->get_request();
			next unless $request;
			my $resp = child_worker($request);
			$conn->force_last_request();
			$conn->send_response($resp);
		}
	}
}
sleep(10000);

sub child_worker
{
	my $data = parse_request(@_);
	if (($data->{method} eq 'POST') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/multipart-uploads$!)) {
		my ($account, $vault) = ($1,$2);
		defined($account)||croak;
		defined($vault)||croak;
		my $partsize = $data->{headers}->{'x-amz-part-size'}||croak;
		my $description = $data->{headers}->{'x-amz-archive-description'}||croak;
		my $upload_id = gen_id(); # TODO: upload ID not archive ID!
		store($account, $vault, 'upload', $upload_id, archive => { partsize => $partsize, description => $description});
		my $resp = HTTP::Response->new(200, "Fine");
		$resp->header('x-amz-multipart-upload-id', $upload_id);
		return $resp;
	} elsif (($data->{method} eq 'PUT') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/multipart-uploads/(.*?)$!)) {
		my ($account, $vault, $upload_id) = ($1,$2);
		defined($account)||croak;
		defined($vault)||croak;
		defined($upload_id)||croak;
	} else {
		confess;
	}
	confess;
}


sub parse_request
{
	my ($request) = @_;
	print $$.$request->dump;
	
	my $method = $request->method();
	my $url = $request->url();
	

    # AUTH	
	my $auth = $request->header('Authorization')||croak;
	#"AWS4-HMAC-SHA256 Credential=$self->{key}/$credentials, SignedHeaders=$signed_headers, Signature=$signature"
	croak unless $auth =~ /^AWS4-HMAC-SHA256\s+(.*)$/;
	my (@pairs) = split(/,\s*/, $1);
	my %data = map { my ($key, $value) = split('=', $_); $key => $value } @pairs;
	
	
	# CRED
	defined($data{'Credential'})||croak;
	
	#"$datestr/$self->{region}/$self->{service}/aws4_request"
	croak unless $data{'Credential'} =~ m!^(.*?)/(.*?)/(.*?)/(.*?)/aws4_request$!;
	my ($key, $datestr, $region, $service) = ($1,$2,$3,$4);
	defined($key)||croak;
	defined($datestr)||croak;
	defined($region)||croak;
	defined($service)||croak;
	croak unless $key eq $config->{key};
	
	my ($kSigning, $kSigning_hex) = get_signature_key($config->{secret}, $datestr, $region, 'glacier');
	
	# HEADERS
	defined($data{'SignedHeaders'})||croak;
	my $signed_headers = $data{'SignedHeaders'};
	my @all_signed_header = split(';', $signed_headers);
	my %a = map {  lc($_) => $request->header($_)  } @all_signed_header;
	my $headers_hash = \%a;
	my $canonical_headers = join("\n", map { lc($_).":".trim($request->header($_)) } @all_signed_header);
	
	# PARAMS
	
	my ($baseurl, $params);
	if ($url =~ m!^([^\?]+)\?(.*)$!) {
		$baseurl = $1;
		$params = \map { my ($k,$v) = split('=', $_); $k => $v } split('&', $2);
	} else {
		$baseurl = $url;
	}
	
	# MISC
	
	my $bodyhash = sha256_hex($request->content);
	my $date8601 = $request->header('x-amz-date');
	defined($date8601)||croak;
	defined($headers_hash->{'x-amz-date'})||croak;
	

    # QUERY_STRING
    	
	my $canonical_query_string = $params ? join ('&', map { "$_=$params->{$_}" } sort keys %{$params}) : ""; # TODO: proper URI encode
	my $canonical_url = "$method\n$baseurl\n$canonical_query_string\n$canonical_headers\n\n$signed_headers\n$bodyhash";
	my $canonical_url_hash = sha256_hex($canonical_url);

	my $string_to_sign = "AWS4-HMAC-SHA256\n$date8601\n$datestr/$region/glacier/aws4_request\n$canonical_url_hash";
	
	my $signature = hmac_hex($kSigning, $string_to_sign);
	croak unless $signature eq $data{'Signature'};

	{ method => $method, params => $params, url => $baseurl, headers => $headers_hash};
}

sub store
{
	my ($account, $vault, $idtype, $id, %data) = @_;
	my $root_dir = $account;
	$root_dir = '_default' if $root_dir eq '-';
	my $full_path = "$ARGV[0]$root_dir/$vault/$idtype/$id";
	mkpath($full_path);
	for my $k (keys %data) {
		confess if -f "$full_path/$k";
		open (F, ">:encoding(UTF-8)", "$full_path/$k");
		print F $json_coder->encode($data{$k});
		close F;
	}
}

sub gen_id
{
	$$."_".time()."_".substr(rand(), 2,10);
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
__END__


