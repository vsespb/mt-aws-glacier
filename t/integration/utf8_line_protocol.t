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
use utf8;
use FindBin;
use lib "$FindBin::RealBin/../", "$FindBin::RealBin/../../lib";
use App::MtAws::LineProtocol qw/encode_data decode_data send_data get_data/;
use Test::More tests => 60;
use Test::Deep;
use Encode;
use bytes;
no bytes;
use TestUtils;
use File::Temp ();

warning_fatal();


my $str = "Тест";

ok (decode_data(encode_data($str)) eq $str);
ok (utf8::is_utf8 decode_data(encode_data($str)) );
ok (!utf8::is_utf8 encode_data($str) );
ok (length(decode_data(encode_data($str))) == 4 );
is (bytes::length(encode_data($str)), 26);

my $str_binary = encode("UTF-8", $str);
my $recorded = decode_data(encode_data($str_binary));
ok ($recorded eq $str_binary);
ok (utf8::is_utf8($recorded) && !utf8::is_utf8($str_binary));

my $TEMP = File::Temp->newdir();
my $mtroot = $TEMP->dirname();
my $tmp_file = "$mtroot/line_proto_test";
our $file = undef;

sub sending
{
	local $file;
	open $file, ">", $tmp_file;
	shift->();
	close $file;
}

sub receiving
{
	local $file;
	open $file, "<", $tmp_file;
	shift->();
	close $file;
}


# should work
{
	my $src = { var => 'test' };
	sending sub {
		ok send_data($file, 'testaction', 'sometaskid', $src);
	};
	receiving sub {
		my ($pid, $action, $taskid, $data) = get_data($file);
		is $pid, $$;
		is $action, 'testaction';
		is $taskid, 'sometaskid';
		cmp_deeply($data, $src);
	}
}

# should work with attachment
{
	my $src = { var => 'test' };
	my $attachment = 'xyz' x 500;
	sending sub {
		ok send_data($file, 'testaction', 'sometaskid', $src, \$attachment);
	};
	receiving sub {
		my ($pid, $action, $taskid, $data, $att) = get_data($file);
		is $pid, $$;
		is $action, 'testaction';
		is $taskid, 'sometaskid';
		is $$att, $attachment;
		cmp_deeply($data, $src);
	}
}

# should work with attachment and utf-8 data, above Latin-1
{
	my $src = { var => 'тест' };
	my $attachment = 'xyz' x 500;
	sending sub {
		ok send_data($file, 'testaction', 'sometaskid', $src, \$attachment);
	};
	receiving sub {
		my ($pid, $action, $taskid, $data, $att) = get_data($file);
		is $pid, $$;
		is $action, 'testaction';
		is $taskid, 'sometaskid';
		is $$att, $attachment;
		cmp_deeply($data, $src);
	}
}

# should work with attachment and utf-8 Latin-1 data
{
	my $c = 'Ñ';
	ok ord $c <= 255;
	my $src = { var => $c.$c.$c };
	my $attachment = encode('UTF-8', 'тест') x 500;
	sending sub {
		ok send_data($file, 'testaction', 'sometaskid', $src, \$attachment);
	};
	receiving sub {
		my ($pid, $action, $taskid, $data, $att) = get_data($file);
		is $pid, $$;
		is $action, 'testaction';
		is $taskid, 'sometaskid';
		is $$att, $attachment;
		cmp_deeply($data, $src);
	}
}


# should work with attachment and utf-8, above Latin-1 data
{
	my $c = 'Ф';
	ok ord $c > 255;
	my $src = { var => $c.$c.$c };
	my $attachment = encode('UTF-8', 'тест') x 500;
	sending sub {
		ok send_data($file, 'testaction', 'sometaskid', $src, \$attachment);
	};
	receiving sub {
		my ($pid, $action, $taskid, $data, $att) = get_data($file);
		is $pid, $$;
		is $action, 'testaction';
		is $taskid, 'sometaskid';
		is $$att, $attachment;
		cmp_deeply($data, $src);
	}
}

# when some ASCII data has UTF-8 bit set
{
	my ($A) = split(' ', 'testaction ФФФ');
	ok utf8::is_utf8($A);
	ok length($A) == bytes::length($A);
	# should work with attachment and utf-8 Latin-1 data
	{
		my $c = 'Ñ';
		ok ord $c <= 255;
		my $src = { var => $c.$c.$c };
		my $attachment = encode('UTF-8', 'тест') x 500;
		sending sub {
			ok send_data($file, $A, 'sometaskid', $src, \$attachment);
		};
		receiving sub {
			my ($pid, $action, $taskid, $data, $att) = get_data($file);
			is $pid, $$;
			is $action, $A;
			is $taskid, 'sometaskid';
			is $$att, $attachment;
			cmp_deeply($data, $src);
		}
	}
	
	
	# should work with attachment and utf-8, above Latin-1 data
	{
		my $c = 'Ф';
		ok ord $c > 255;
		my $src = { var => $c.$c.$c };
		my $attachment = encode('UTF-8', 'тест') x 500;
		sending sub {
			ok send_data($file, $A, 'sometaskid', $src, \$attachment);
		};
		receiving sub {
			my ($pid, $action, $taskid, $data, $att) = get_data($file);
			is $pid, $$;
			is $action, $A;
			is $taskid, 'sometaskid';
			is $$att, $attachment;
			cmp_deeply($data, $src);
		}
	}
}
# should raise excaption if attachment is UTF-8, above Latin-1 string
{
	my $src = { var => 'test' };
	my $c = 'Ф';
	ok ord $c > 255;
	my $attachment = $c x 500;
	sending sub {
		ok ! defined eval { send_data($file, 'testaction', 'sometaskid', $src, \$attachment); 1 };
		ok $@ =~ /Attachment should be a binary string/i;
	};
}

# should raise excaption if attachment is UTF-8, Latin-1 string
{
	my $src = { var => 'test' };
	my $c = 'Ñ';
	ok ord $c <= 255;
	my $attachment = $c x 500;
	sending sub {
		ok ! defined eval { send_data($file, 'testaction', 'sometaskid', $src, \$attachment); 1 };
		ok $@ =~ /Attachment should be a binary string/i;
	};
}

unlink $tmp_file;
1;
