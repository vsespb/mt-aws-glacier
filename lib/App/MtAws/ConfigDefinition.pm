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

package App::MtAws::ConfigDefinition;

use strict;
use warnings;
use utf8;

use App::MtAws::ConfigEngineNew;

sub filter_options
{
	optional(qw/include exclude/);
}

sub check_base_dir
{
	if ( present('base-dir') && !present('dir') ) {
		error('base-dir can be used only with dir');
	} elsif ( present('dir') ) {
		optional('base-dir');
	} else {
		return;
	}
}

sub check_dir_or_relname
{
	
	if (present('filename')) {
		custom('data-type', 'filename'), mandatory('filename'), do {
			if (present('set-rel-filename')) {
				if (present('dir')) {
					error('set-rel-filename and dir are mutual exclusive')
				} else {
					custom('name-type', 'rel-filename'), mandatory('set-rel-filename');
				}
			} elsif (present('dir')) {
				custom('name-type', 'dir'), mandatory('dir');
			} else {
				error('please specify set-rel-filename or dir')
			}
		}
	} elsif (present('stdin')) {
		if (present('set-rel-filename')) {
			if (present('dir')) {
				error('set-rel-filename and dir are mutual exclusive')
			} else {
				custom('name-type', 'rel-filename'), custom('data-type', 'stdin'), mandatory('set-rel-filename'), mandatory('stdin')
			}
		} else {
			error('need use set-rel-filename together with stdin')
		}
	} else {
		error('please specify filename or stdin')
	}
}

sub download_options
{
	mandatory('dir'), check_base_dir, optional('chunksize');
}

sub check_wait
{
	if (present('wait')) {
		mandatory('wait'), download_options
	} else {
		return;
	}
}

sub get_config
{
	my (%args);
	my $c  = App::MtAws::ConfigEngineNew->new(%args);
	
	$c->define(sub {
		my @remote = option qw/concurrency key vault secret region protocol/;
		my @dir_or_relname = option qw/set-rel-filename dir/;
		option qw/base-dir include exclude partsize journal filename stdin wait chunksize zz/;
		
		
		validation 'concurrency', 'concurrency should be less than 30', sub { $_ < 30 };
		
		command 'sync' => sub {
			 mandatory( mandatory(@remote), 'journal',  mandatory('dir'), check_base_dir, optional('partsize'), filter_options ); 
		};
		command 'upload-file' => sub {
			mandatory(@remote), mandatory('journal'),  scope('dir', check_dir_or_relname, check_base_dir), optional('partsize'); 
		};
		command 'retrieve-file' => sub {
			validate mandatory(@remote), mandatory('journal'),  check_wait, scope('dir', check_dir_or_relname, check_base_dir), optional 'partsize' 
		};
	});
	return $c;
}

1;
__END__
		command 'retrieve' => sub {
			mandatory(@remote), mandatory 'journal',  check_wait, filter_options
		};
		
		command 'download' => sub {
			mandatory(@remote), mandatory 'journal',  download_options, filter_options 
		};
		
		command 'upload-file' => sub {
			mandatory(@remote), mandatory 'journal',  check_dir_or_relname, check_base_dir, optional 'partsize' 
		};
		
		command 'retrieve-file' => sub {
			mandatory(@remote), mandatory 'journal',  check_wait, check_dir_or_relname, check_base_dir, optional 'partsize' 
		};
