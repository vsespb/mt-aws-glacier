#!/usr/bin/perl


use warnings;
use strict;
use HTTP::Daemon;
use HTTP::Daemon::SSL;
use Carp;
use POSIX;
use File::Path;
use Data::Dumper;
use JSON::XS;
use lib qw{.. ../..};
use App::MtAws::TreeHash;
use Digest::SHA qw(hmac_sha256 hmac_sha256_hex sha256_hex sha256);
use Time::Local;
use Fcntl qw/LOCK_EX/;


my $proto = $ARGV[0]||die "Specify http|https";
my $tmp_folder = $ARGV[1]||die "Specify temporary folder";
my $children_count = 20;
my $daemon = $proto eq 'http' ? HTTP::Daemon->new(LocalAddr => '',	LocalPort => 9901, ReuseAddr => 1) : HTTP::Daemon::SSL->new(LocalAddr => '',	LocalPort => 9901, ReuseAddr => 1);
$daemon || die $daemon;
my $json_coder = JSON::XS->new->utf8->allow_nonref;

my $config = { key=>'AKIAJ2QN54K3SOFABCDE', secret => 'jhuYh6d73hdhGndk1jdHJHdjHghDjDkkdkKDkdkd'};
my $seq_n = 0;


init_seq_number();

for my $n (1..$children_count) {
	if (!fork()) {
		while (my $conn = $daemon->accept) {
#			if (rand > 0.9) {
#				close $conn;
#				next;
#			}
			my $request = $conn->get_request();
			next unless $request;
			my $resp = child_worker($conn, $request);
			if ($resp) {
				$conn->force_last_request();
				$conn->send_response($resp);
			}
		}
	}
}
sleep(10000);

sub child_worker
{
	my ($conn, $request) = @_;
	my $data = parse_request($request);
	# CREATE MULTIPART UPLOAD
	if (($data->{method} eq 'POST') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/multipart-uploads$!)) {
		my ($account, $vault) = ($1,$2);
		defined($account)||croak;
		defined($vault)||croak;
		my $partsize = $data->{headers}->{'x-amz-part-size'}||croak;
		croak unless $partsize >=1024 && ($partsize % 1048576 == 0) && (   ($partsize != 0) && (($partsize & ($partsize - 1)) == 0)   );


		my $description = $data->{headers}->{'x-amz-archive-description'}||croak;
		my $upload_id = gen_id(); # TODO: upload ID not archive ID!
		store($account, $vault, 'upload', $upload_id, archive => { partsize => $partsize, description => $description});
		my $resp = HTTP::Response->new(200, "Fine");
		$resp->header('x-amz-multipart-upload-id', $upload_id);
		return $resp;
		#		die "With current partsize=$self->{partsize} we will exceed 10000 parts limit for the file $self->{filename} (filesize $filesize)" if ($filesize / $self->{partsize} > 10000);
		#				die "Part size should be power of two" unless ($partsize != 0) && (($partsize & ($partsize - 1)) == 0);
	# MULTIPART UPLOAD PART
	} elsif (($data->{method} eq 'PUT') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/multipart-uploads/(.*?)$!)) {
		my ($account, $vault, $upload_id) = ($1,$2,$3);
		defined($account)||croak;
		defined($vault)||croak;
		defined($upload_id)||croak;

		croak unless $data->{headers}->{'content-type'} eq 'application/octet-stream';
		croak unless $data->{headers}->{'content-length'} > 0; # TODO: check length equal to partsize!
		croak unless defined($data->{headers}->{'x-amz-content-sha256'});
		croak unless defined($data->{headers}->{'x-amz-sha256-tree-hash'});
		croak unless defined($data->{headers}->{'content-range'});

		croak unless $data->{headers}->{'content-range'} =~ /^bytes (\d+)\-(\d+)\/\*$/;
		my ($start, $finish) = ($1,$2);
		croak unless $finish >= $start;
		my $len = $finish - $start + 1;

		my $archive = fetch($account, $vault, 'upload', $upload_id, 'archive')->{archive};

		croak "$data->{headers}->{'content-length'} != $len" if ($data->{headers}->{'content-length'} != $len);
		croak "$archive->{partsize} > $len" if ($len > $archive->{partsize});

		croak unless sha256_hex(${$data->{bodyref}}) eq $data->{headers}->{'x-amz-content-sha256'};

		my $part_th = App::MtAws::TreeHash->new();
		$part_th->eat_data($data->{bodyref});
		$part_th->calc_tree();
		my $th = $part_th->get_final_hash();

		croak "$th ne ".$data->{headers}->{'x-amz-sha256-tree-hash'} unless $th eq $data->{headers}->{'x-amz-sha256-tree-hash'};

		store_binary($account, $vault, 'upload', $upload_id, "part_${start}_${finish}", $data->{bodyref});
		my $resp = HTTP::Response->new(201, "Fine");
		return $resp;

	# FINISH MULTIPART UPLOAD
	} elsif (($data->{method} eq 'POST') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/multipart-uploads/(.*?)$!)) {
		my ($account, $vault, $upload_id) = ($1,$2,$3);
		defined($account)||croak;
		defined($vault)||croak;
		defined($upload_id)||croak;

		croak unless defined($data->{headers}->{'x-amz-archive-size'});
		my $len = $data->{headers}->{'x-amz-archive-size'};
		croak unless defined($data->{headers}->{'x-amz-sha256-tree-hash'});
		my $treehash = $data->{headers}->{'x-amz-sha256-tree-hash'};

		my $archive_upload = fetch($account, $vault, 'upload', $upload_id, 'archive')->{archive};
		my $bpath = basepath($account, $vault, 'upload', $upload_id);

		my $parts = {};
		while (<$bpath/part_*>) {
			/part_(\d+)_(\d+)$/;
			my ($start, $finish) = ($1, $2);
			my $len = $finish - $start + 1;

			confess "$archive_upload->{partsize} > $len" if ($len > $archive_upload->{partsize});

			$parts->{$start} = { start => $start, finish => $finish, size => $len, filename => $_ };
		}

		my $currstart = 0;

		my @parts_a;
		my $last_part = 0;
		while ($currstart < $len) {
			croak "previous part was smaller than partsize" if $last_part;
			my $p = $parts->{$currstart}||croak "Part $currstart not found (len = $len)";
			confess "$archive_upload->{partsize} > $len" if ($p->{size} > $archive_upload->{partsize});
			$last_part = 1 if ($p->{size} < $archive_upload->{partsize});
			push @parts_a, $p->{filename};
			$currstart = $p->{finish}+1;
			croak if $currstart > $len;
		}

		my $archive_id = gen_id();
		my $archive_path = basepath($account, $vault, 'archive', $archive_id, 'data');

		my $part_th = App::MtAws::TreeHash->new();

		open OUT, ">$archive_path" || croak $archive_path;
		binmode OUT;
		for my $f (@parts_a) {
			open IN, "<$f";
			binmode IN;
			sysread(IN, my $buf, -s $f);
			close IN;
			$part_th->eat_data(\$buf);
			syswrite OUT, $buf;
		}
		close OUT;
		$part_th->calc_tree();
		my $th = $part_th->get_final_hash();

		# TODO: copy archive metadata as well!

		croak unless $th eq $treehash;

		store($account, $vault, 'archive', $archive_id, archive => {
			id => $archive_id,
			creation_timestamp => time(),
			partsize => $archive_upload->{partsize}||confess,
			description => $archive_upload->{description}||confess,
			treehash => $treehash,
			archive_size => $len,
		});

		my $resp = HTTP::Response->new(200, "Fine");
		$resp->header('x-amz-archive-id', $archive_id);
		return $resp;

	# CREATE JOB (to restore file/retrieve inventory)
	} elsif (($data->{method} eq 'POST') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/jobs$!)) {
		my ($account, $vault) = ($1,$2);
		defined($account)||croak;
		defined($vault)||croak;

		croak unless defined($data->{headers}->{'content-type'});
		croak unless $data->{headers}->{'content-type'} eq 'application/x-www-form-urlencoded; charset=utf-8';

		my $json_coder = JSON::XS->new->allow_nonref;
		my $postdata = $json_coder->decode(${$data->{bodyref}});

		if ($postdata->{Type} eq 'archive-retrieval') {
			my $archive_id = $postdata->{ArchiveId};
			defined($archive_id)||croak;
			croak unless scalar keys %$postdata == 2; # TODO deep comparsion

			my $archive = fetch($account, $vault, 'archive', $archive_id, 'archive')->{archive}||confess;
			store($account, $vault, 'archive', $archive_id, retrieved => { retrieved => 1}); # TODO: remove

			my $job_id = gen_id();
			my $now = time();
			store($account, $vault, 'jobs', $job_id, job => {
				type => 'archive-retrieval',
				id => $job_id,
				archive_id => $archive_id,
				archive_size => $archive->{archive_size}||confess,
				treehash => $archive->{treehash}||confess,
				completion_date => strftime("%Y%m%dT%H%M%SZ", gmtime($now)),
				creation_date => strftime("%Y%m%dT%H%M%SZ", gmtime($now)),
			});

			my $resp = HTTP::Response->new(202, "Accepted");
			$resp->header('x-amz-job-id', $job_id);
			return $resp;

		} elsif ($postdata->{Type} eq 'inventory-retrieval') {
			my $now = time();

			confess "unimplemented" if exists $postdata->{InventoryRetrievalParameters};

			my $bpath = basepath($account, $vault, 'archive');
			my $data = {
				"VaultARN" => "arn:aws:glacier:us-east-1:$account:vaults/$vault", # TODO: correct string with region
				"InventoryDate" => strftime("%Y%m%dT%H%M%SZ", gmtime($now)),
				"ArchiveList" => [],
			};
			my $archive_list = $data->{"ArchiveList"};
			while (<$bpath/*>) { #TODO: sort
				my $a = fetch_raw("$_/archive");
				push @$archive_list, {
					ArchiveId => $a->{id}||confess,
					ArchiveDescription => $a->{description}||confess, # TODO: what if '0' ?
					CreationDate => strftime("%Y%m%dT%H%M%SZ", gmtime($a->{creation_timestamp}||confess)),
					Size => $a->{archive_size}||confess, # TODO if 0 ?
					SHA256TreeHash => $a->{treehash}||confess,
				};
			}

			my $output = do {
				if ($postdata->{Format} eq 'JSON') {
					JSON::XS->new->allow_nonref->ascii->pretty->encode($data);
				} elsif ($postdata->{Format} eq 'CSV')  {
					join("\n",
						"ArchiveId,ArchiveDescription,CreationDate,Size,SHA256TreeHash",
						map {
							my $descr = $_->{ArchiveDescription};
							$descr =~ s!\\!\\\\!g;
							$descr =~ s!\"!\\\"!g;
							qq{$_->{ArchiveId},"$descr",$_->{CreationDate},$_->{Size},$_->{SHA256TreeHash}}
						} @$archive_list
					);
				} else {
					confess "Unknown inventory format $postdata->{Format}";
				}
			};

			my $job_id = gen_id();
			store($account, $vault, 'jobs', $job_id,
				job => {
					id => $job_id,
					type => 'inventory-retrieval',
					format => $postdata->{Format},
					description => $postdata->{Description},
					completion_date => strftime("%Y%m%dT%H%M%SZ", gmtime($now)),
					creation_date => strftime("%Y%m%dT%H%M%SZ", gmtime($now)),
				},
			);
			store_binary($account, $vault, 'jobs', $job_id, 'output', \$output); # TODO: by ref

			my $resp = HTTP::Response->new(202, "Accepted");
			$resp->header('x-amz-job-id', $job_id);
			return $resp;
		} else {
			croak;
		}
	# LIST JOBS (to restore file/retrieve inventory)
	} elsif (($data->{method} eq 'GET') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/jobs$!)) {
		my ($account, $vault) = ($1,$2);
		defined($account)||croak;
		defined($vault)||croak;

		my $limit = 50;
		my @jobs;
		if (defined($data->{params}->{marker})) {
			my $jobsref = fetch($account, $vault, 'job-listing-markers', $data->{params}->{marker}, 'marker')->{marker}||confess;
			@jobs = @$jobsref;
		} else {
			my $bpath = basepath($account, $vault, 'jobs');
			my @listing = sort <$bpath/*>;
			local $_;
			while (@listing) {
				$_ = shift @listing;
				my $j = fetch_raw("$_/job");

				if ($j->{type} eq 'archive-retrieval') {
					push @jobs, {
						Action => 'ArchiveRetrieval',
						ArchiveId => $j->{archive_id}||confess("1 archive_id"),
						ArchiveSizeInBytes => $j->{archive_size}||confess("2 archive size"),
						ArchiveSHA256TreeHash => $j->{treehash}||confess("3 treehash"),
						Completed => \1,
						CompletionDate => $j->{completion_date}||confess("4 completion date"),
						CreationDate => $j->{creation_date}||confess("5 creation date"),
						StatusCode => "Succeeded",
						JobId => $j->{id}||confess("6 job id"),
					} ;
				} elsif ($j->{type} eq 'inventory-retrieval') {
					push @jobs, {
						Action => 'InventoryRetrieval',
						Completed => \1,
						CompletionDate => $j->{completion_date}||confess("4 completion date"),
						CreationDate => $j->{creation_date}||confess("5 creation date"),
						StatusCode => "Succeeded",
						JobDescription => $j->{description},
						InventoryRetrievalParameters => { StartDate => undef, EndDate => undef, Limit => undef, Marker => undef},
						JobId => $j->{id}||confess("6 job id"),
					} ;
				} else {
					croak;
				}
			}
		}
		my $resp = HTTP::Response->new(200, "Fine");
		$resp->content(get_next_jobs($account, $vault, $limit, @jobs));
		return $resp;
	# DOWNLOAD FILE OR INVENTORY
	} elsif (($data->{method} eq 'GET') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/jobs/(.*?)/output$!)) {
		my ($account, $vault, $job_id) = ($1,$2,$3);
		defined($account)||croak;
		defined($vault)||croak;
		defined($job_id)||croak;

		my $job = fetch($account, $vault, 'jobs', $job_id, 'job')->{job}||croak;

		if ($job->{type} eq 'archive-retrieval') {
			my $archive_id = $job->{archive_id}||confess;
			my $archive = fetch($account, $vault, 'archive', $archive_id, 'archive')->{archive}||croak; # TODO: what if archive already deleted?
			$archive->{treehash} or confess;
			my $archive_path = basepath($account, $vault, 'archive', $archive_id, 'data');
			if ($data->{headers}->{range}) { # SEGMENT DOWNLOAD
				my ($start, $end) = $data->{headers}->{range} =~ /bytes=(\d+)\-(\d+)/;
				my $total = -s $archive_path;
				confess unless defined($start) && defined($end);
				confess if $end < $start;
				my $len = $end - $start + 1;
				open (my $in, "<", $archive_path)||confess;
				binmode $in;
				print STDERR "POS $start,$end,$len\n";
				seek $in, $start, SEEK_SET;
				my $r = read($in, my $buf, $len);
				$r == $len or confess "$r != $len";
				close $in;

				my $treehash = App::MtAws::TreeHash->new();
				$treehash->eat_data($buf);
				$treehash->calc_tree();
				my $th = $treehash->get_final_hash();

				$conn->send_basic_header(206);
				print $conn header_line('Content-Length', length($buf));
				print $conn header_line('x-amz-sha256-tree-hash', $th);
				print $conn header_line('Content-Range', "bytes ${start}-${end}/$total");
				$conn->send_crlf;
				print $conn $buf;
				return;
			} else {
				print Dumper({archive_id=>$archive_id, archive_path=>$archive_path, archive=>$archive, job=>$job});
				my $total = -s $archive_path;
				open (my $in, "<", $archive_path)||confess;
				binmode $in;

				my $chunk_size = 4096;

				$conn->send_basic_header(200);
				print $conn header_line('Content-Length', $total);
				print $conn header_line('x-amz-sha256-tree-hash', $archive->{treehash});
				$conn->send_crlf;

				while(my $res = read($in, my $buf, $chunk_size)) {
					print $conn $buf;
				}
				return;
			}
		} elsif ($job->{type} eq 'inventory-retrieval'){
			my $output = fetch_binary($account, $vault, 'jobs', $job_id, 'output');
			$conn->send_basic_header(200);
			print $conn header_line('Content-Length', length($$output));
			print $conn header_line('Content-Type', $job->{format} eq 'JSON' ? 'application/json' : 'text/csv');
			$conn->send_crlf;
			print $conn $$output;
			return;
		} else {
			croak;
		}
	# DELETE FILE
	} elsif (($data->{method} eq 'DELETE') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)/archives/(.*?)$!)) {
		my ($account, $vault, $archive_id) = ($1,$2,$3);
		defined($account)||croak;
		defined($vault)||croak;
		defined($archive_id)||croak;
		fetch($account, $vault, 'archive', $archive_id, 'archive'); # TEST - WHAT IF THERE IS NO ARCHIVE! WILL CONFESS THEN
		my $bpath = basepath($account, $vault, 'archive', $archive_id)||croak;# TODO: WE SHOULD NOT CREATE PATH IF IT'S NOT EXISTS ?
		rmtree($bpath) if -d $bpath && $bpath =~ m!archive/\d!;
		my $resp = HTTP::Response->new(200, "Fine");
		return $resp;
	# CREATE VAULT
	} elsif (($data->{method} eq 'PUT') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)$!)) {
		my ($account, $vault) = ($1,$2);
		create_vault($account, $vault);
		my $resp = HTTP::Response->new(201, "Created");
		$resp->header('x-amzn-RequestId', gen_id());
		return $resp;
	} elsif (($data->{method} eq 'DELETE') && ($data->{url} =~ m!^/(.*?)/vaults/(.*?)$!)) {
		my ($account, $vault) = ($1,$2);
		delete_vault($account, $vault);
		my $resp = HTTP::Response->new(204, "No Content");
		$resp->header('x-amzn-RequestId', gen_id());
		return $resp;
	} else {
		confess;
	}
	confess;
}


sub header_line
{
	my ($k, $v) = @_;
	"$k: ".$v."\015\012";
}

sub get_next_jobs
{
	my ($account, $vault, $limit, @jobs) = @_;
	my @active_jobs = splice @jobs, 0, $limit;
	my $response_body;
	if (@jobs) {
		my $marker_id = gen_id();
		store($account, $vault, 'job-listing-markers', $marker_id, marker => \@jobs);
		$response_body = $json_coder->encode({
			JobList => \@active_jobs,
			Marker => $marker_id,
		});
	} else {
		$response_body = $json_coder->encode({
			JobList => \@active_jobs,
		});
	}

	$response_body;
}

sub parse_request
{
	my ($request) = @_;
#	print $$.$request->dump;

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
		my %h = map { my ($k,$v) = split('=', $_); $k => $v } split('&', $2);
		$params = \%h;
	} else {
		$baseurl = $url;
	}

	# MISC

	my $bodyref = \$request->content;
	my $bodyhash = sha256_hex($$bodyref);

	croak "The value passed in as x-amz-content-sha256 does not match the computed payload hash"
		if $request->header('x-amz-content-sha256') && $bodyhash ne $request->header('x-amz-content-sha256');

	my $date8601 = $request->header('x-amz-date');
	defined($date8601)||croak;
	defined($headers_hash->{'x-amz-date'})||croak;

	# TODO: check $date8601 vs current time !

    # QUERY_STRING

	my $canonical_query_string = $params ? join ('&', map { "$_=$params->{$_}" } sort keys %{$params}) : ""; # TODO: proper URI encode
	my $canonical_url = "$method\n$baseurl\n$canonical_query_string\n$canonical_headers\n\n$signed_headers\n$bodyhash";
	my $canonical_url_hash = sha256_hex($canonical_url);

	my $string_to_sign = "AWS4-HMAC-SHA256\n$date8601\n$datestr/$region/glacier/aws4_request\n$canonical_url_hash";

	my $signature = hmac_hex($kSigning, $string_to_sign);
	croak unless $signature eq $data{'Signature'};

	{ method => $method, params => $params, url => $baseurl, headers => $headers_hash, bodyref => $bodyref};
}


sub basepath
{
	my ($account, $vault, $idtype, $id, $key) = @_;
	my $root_dir = $account;
	$root_dir = '_default' if $root_dir eq '-';
	my $path = "$tmp_folder$root_dir";
	mkpath($path);
	$path .= "/$vault";
	confess $path unless -d $path;
	$path .= "/$idtype";
	$path .= "/$id" if defined($id);
	mkpath($path);
	$path .= "/$key" if defined($key);
	print "RETURN [$path]\n";
	return $path;
}

sub create_vault
{
	my ($account, $vault) = @_;
	my $root_dir = $account;
	$root_dir = '_default' if $root_dir eq '-';
	my $path = "$tmp_folder$root_dir";
	mkpath($path);
	$path .= "/$vault";
	mkpath($path);
	return $path;
}

sub delete_vault
{
	my ($account, $vault) = @_;
	my $root_dir = $account;
	$root_dir = '_default' if $root_dir eq '-';
	my $path = "$tmp_folder$root_dir";
	mkpath($path);
	$path .= "/$vault";
	confess unless -d $path;
	confess "vault not empty" if glob("$path/archive/*");
	rmtree($path);
	return $path;
}

sub store
{
	my ($account, $vault, $idtype, $id, %data) = @_;
	for my $k (keys %data) {
		my $path = basepath($account, $vault, $idtype, $id, $k);
		open (F, ">:encoding(UTF-8)", $path);
		print F $json_coder->encode($data{$k});
		close F;
	}
}

sub store_binary
{
	my ($account, $vault, $idtype, $id, $name, $dataref) = @_;
	my $path = basepath($account, $vault, $idtype, $id, $name);
	open (F, ">", $path);
	binmode F;
	syswrite F, $$dataref;
	close F;
}

sub fetch
{
	my ($account, $vault, $idtype, $id, @data) = @_;
	my $result = {};
	for my $k (@data) {
		my $path = basepath($account, $vault, $idtype, $id, $k);
		$result->{$k} = fetch_raw($path);
	}
	return $result;
}

sub fetch_binary
{
	my ($account, $vault, $idtype, $id, $name) = @_;
	my $path = basepath($account, $vault, $idtype, $id, $name);
	open (F, "<:encoding(UTF-8)", $path);
	sysread(F, my $buf, -s $path);
	close F;
	return undef unless defined($buf);
	\$buf;
}

sub fetch_raw
{
	my ($path) = @_;
	open (my $f, "<:encoding(UTF-8)", $path) or confess;
	sysread($f, my $buf, -s $path);
	close $f;
	$json_coder->decode($buf);
}

sub init_seq_number
{
	my $countfile = "$tmp_folder/seq.count";
	open my $count_write, ">", $countfile or confess "$!";
	print ($count_write "1\n") or confess "$!";
	close $count_write or confess "$!";
}

sub seq_number
{
	my $lockfile = "$tmp_folder/seq.lock";
	my $countfile = "$tmp_folder/seq.count";
	open my $lock, ">", $lockfile or confess "$!";
	flock $lock, LOCK_EX or confess "$!";

	open my $count_read, "<", $countfile or confess "$!";
	my $cnt = <$count_read>;
	confess unless $cnt;
	chomp $cnt;
	close $count_read or confess "$!";

	$cnt++;

	open my $count_write, ">", $countfile or confess "$!";
	print ($count_write $cnt, "\n") or confess "$!";
	close $count_write or confess "$!";


	close $lock or confess "$!";

	$cnt;
}

sub gen_id
{
	sprintf("%011d_%011d_%05d_%05d_%s", seq_number(), time(), ++$seq_n, $$, substr(rand(), 2,10));
}


# TODO: use code from common codebase, make sure it's tested
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
