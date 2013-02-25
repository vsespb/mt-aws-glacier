#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::RealBin/lib";
use App::MtAws::ConfigDefinition;
use Data::Dumper;


my $c = App::MtAws::ConfigDefinition::get_config;
my $res = $c->parse_options(@ARGV);
#print Dumper $c;
print join("\n", @{$res->{error_texts}});
print "\n";