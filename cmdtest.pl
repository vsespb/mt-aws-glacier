#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::RealBin/lib";
use App::MtAws::ConfigDefinition;

my $c = App::MtAws::ConfigDefinition::get_config;
$c->parse_options(@ARGV);
