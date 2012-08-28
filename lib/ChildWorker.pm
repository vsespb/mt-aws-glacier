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

package ChildWorker;

use LineProtocol;
use GlacierRequest;
use strict;
use warnings;
use File::Basename;
use File::Path qw/make_path/;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    $self->{fromchild}||die;
    $self->{tochild}||die;
    $self->{key}||die;
    $self->{region}||die;
    $self->{secret}||die;
    $self->{vault}||die;
    bless $self, $class;
    return $self;
}

sub process
{
	my ($self) = @_;
	
	my $tochild = $self->{tochild};
	my $fromchild = $self->{fromchild};
	my $disp_select = IO::Select->new();
	$disp_select->add($tochild);
	while (my @ready = $disp_select->can_read()) {
	    for my $fh (@ready) {
			if (eof($fh)) {
				$disp_select->remove($fh);
				return;
			}
			my ($taskid, $action, $data, $attachmentref) = get_command($fh);
			
			my $result = undef;
			
			my $console_out = undef;
			if ($action eq 'create_upload') {
				my $uploadid = GlacierRequest->create_multipart_upload($self->{region}, $self->{key}, $self->{secret}, $self->{vault}, $data->{partsize});
				return undef unless $uploadid;
				$result = { upload_id => $uploadid };
				$console_out = "Created an upload_id $uploadid";
			} elsif ($action eq "upload_part") {
				my $r = GlacierRequest->upload_part($self->{region}, $self->{key}, $self->{secret}, $self->{vault}, $data->{upload_id}, $attachmentref, $data->{start}, $data->{part_final_hash});
				return undef unless $r;
				$result = { uploaded => $data->{start} } ;
				$console_out = "Uploaded part for $data->{filename} at offset [$data->{start}]";
			} elsif ($action eq 'finish_upload') {
				my $archive_id = GlacierRequest->finish_multipart_upload($self->{region}, $self->{key}, $self->{secret}, $self->{vault}, $data->{upload_id}, $data->{filesize}, $data->{final_hash});
				return undef unless $archive_id;
				$result = { final_hash => $data->{final_hash}, archive_id => $archive_id, journal_entry => time()." CREATED $archive_id $data->{filesize} $data->{final_hash} $data->{relfilename}" };
				$console_out = "Finished $data->{filename} hash [$data->{final_hash}] archive_id [$archive_id]";
			} elsif ($action eq 'delete_archive') {
				my $r = GlacierRequest->delete_archive($self->{region}, $self->{key}, $self->{secret}, $self->{vault}, $data->{archive_id});
				return undef unless $r;
				$result = { journal_entry => time()." DELETED $data->{archive_id} $data->{relfilename}" };
				$console_out = "Deleted $data->{relfilename} archive_id [$data->{archive_id}]";
			} elsif ($action eq 'retrieval_download_job') {
				make_path(dirname($data->{filename}));
				my $r = GlacierRequest->retrieval_download_job($self->{region}, $self->{key}, $self->{secret}, $self->{vault}, $data->{jobid}, $data->{filename});
				$result = { response => $r };
				$console_out = "Download Archive $data->{filename}";
			} elsif ($action eq 'retrieve_archive') {
				my $r = GlacierRequest->retrieve_archive($self->{region}, $self->{key}, $self->{secret}, $self->{vault}, $data->{archive_id});
				return undef unless $r;
				$result = { journal_entry => time()." RETRIEVE_JOB $data->{archive_id}" };
				$console_out = "Retrieve Archive $data->{archive_id}";
			} elsif ($action eq 'retrieval_fetch_job') {
				my $r = GlacierRequest->retrieval_fetch_job($self->{region}, $self->{key}, $self->{secret}, $self->{vault});
				return undef unless $r;
				$result = { response => $r };
				$console_out = "Retrieve Job List";
			} else {
				die $action;
			}
			$result->{console_out}=$console_out;
			send_response($fromchild, $taskid, $result);
	    }
	}
}


sub get_command
{
  my ($fh) = @_;
  my $response = <$fh>;
  chomp $response;
  my ($taskid, $action, $attachmentsize, $data_e) = split(/\t/, $response);
  my $attachment = undef;
  if ($attachmentsize) {
  	read $fh, $attachment, $attachmentsize;
  }
  my $data = decode_data($data_e);
  return ($taskid, $action, $data, $attachment ? \$attachment : undef);
}


sub send_response
{
  my ($fh, $taskid, $data) = @_;
  my $data_e = encode_data($data);
  my $line = "$$\t$taskid\t$data_e\n";
  print $fh $line;
}



1;
