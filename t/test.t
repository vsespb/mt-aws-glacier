#!/usr/bin/env perl

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

use TAP::Harness;
use strict;
use warnings;
use utf8;

my $harness = TAP::Harness->new({
    formatter_class => 'TAP::Formatter::Console',
    exec => ['perl'],
    merge           => 1,
 #   verbosity       => 1,
    normalize       => 1,
    color           => 1,
    jobs			=> 8,
    switches	=> '-MDevel::Cover'
});
$harness->runtests(
    'integration/journal.t',
    'integration/config_read_config.t',
    'integration/config_engine_config_file.t',
    'integration/utf8_journal.t',
    'integration/utf8_line_protocol.t',
    'integration/utf8.t',
    'integration/t_treehash.t',
    'integration/metadata.t',
    'integration/metadata_mt1.t',
    'integration/journal_readwrite.t',
    'unit/journal_readjournal.t',
    'unit/journal_writejournal.t',
    'unit/journal_readfiles.t',
    'unit/journal_sanity.t',
    'unit/config_engine_parse.t',
    'unit/u_treehash.t',
    'unit/metadata.t',
    'unit/journal_openmodes.t',
    'integration/config_engine_v078.t',
    'integration/config_engine_v082.t',
);
