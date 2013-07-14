#!/usr/bin/perl

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

use strict;
use warnings;
use Test::More tests => 1;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use TestUtils;
use App::MtAws::Utils;
use File::Temp;
use Carp;
use Fcntl qw/SEEK_SET LOCK_EX LOCK_UN SEEK_SET/;
use IO::Pipe;
use Time::HiRes qw/usleep/;

warning_fatal();

my $TEMP = File::Temp->newdir();
my $mtroot = $TEMP->dirname();

my $filename = "$mtroot/testlock";

open F, ">$filename";
print F 1;
close F;

my $fromchild = new IO::Pipe;
my $tochild = new IO::Pipe;

sub _flock { flock($_[0], $_[1]); }
#sub _flock { 1 }

if (fork()) {
   $fromchild->reader();
   $fromchild->autoflush(1);
   $fromchild->blocking(1);
   binmode $fromchild;
   
   $tochild->writer();
   $tochild->autoflush(1);
   $tochild->blocking(1);
   binmode $tochild;
	
	open_file(my $fh, $filename, mode => '+<', binary => 1);
	print $tochild "open\n";
	_flock $fh, LOCK_EX or confess;
	$fh->flush();
	$fh->autoflush(1);
	print $fh "1234\n";
	print $tochild "lock\n";
	usleep(300); 
	seek $fh, 0, SEEK_SET;
	print $fh "ABCD\n";
	flock $fh, LOCK_UN or confess;
	is scalar <$fromchild>, "OK\n"
} else {
   $fromchild->writer();
   $fromchild->autoflush(1);
   $fromchild->blocking(1);
   binmode $fromchild; 

   $tochild->reader();
   $tochild->autoflush(1);
   $tochild->blocking(1);
   binmode $tochild;
   
	confess unless (scalar <$tochild> eq "open\n");
	open_file(my $fh, $filename, mode => '+<', binary => 1) or confess;
	confess unless (scalar <$tochild> eq "lock\n");
	_flock $fh, LOCK_EX or confess;
	$fh->flush();
	$fh->autoflush(1);
	seek $fh, 0, SEEK_SET;
	confess unless (scalar <$fh> eq "ABCD\n");
	print $fromchild "OK\n";
	usleep(300); # protect parent from SIGCHLD
}
1;
