#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::RealBin/lib";
use App::MtAws::ConfigDefinition;

my $c = App::MtAws::ConfigDefinition::get_config;
my (undef, undef, undef, undef, $errors) = $c->parse_options(@ARGV);
print join("\n", @$errors);
print "\n";