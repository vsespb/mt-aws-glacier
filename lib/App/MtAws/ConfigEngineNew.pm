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

package App::MtAws::ConfigEngineNew;

use Getopt::Long;
use Encode;
use Carp;
use List::Util qw/first/;

use strict;
use warnings;
use utf8;
			use Data::Dumper;
require Exporter;                                                                                                                                                                                                                                                              
use base qw/Exporter/;                                                                                                                                                                                                                                                         
                                                                                                                                                                                                                                                                               
our @EXPORT = qw/option command validation
				mandatory optional validate scope
				present set error/;

our $context; 

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	return $self;
}

sub define($&)
{
	my ($self, $block) = @_;
	$context = $self;
	$block->();
}

sub parse_options
{
	(my $self, local @ARGV) = @_; # we override @ARGV here, cause GetOptionsFromArray is not exported on perl 5.8.8
	
	my @getopts = map { "$_=s" } keys %{$self->{options}};
	GetOptions(\my %results, @getopts);
	
	@{$self->{options}->{$_}}{qw/value source/} = ($results{$_}, 'option') for keys %results;
	
	$self->{commands}->{shift @ARGV	}->{cb}->();
	
	print Dumper($self->{errors});
	print Dumper [grep { (!$_->{seen}) && defined($_->{value}) } values %{$self->{options}}];
	#print Dumper($self);
}

sub assert_option {	($context->{options}->{$_} && $_) || confess "undeclared option $_"; }

sub option(@) {
	map { $context->{options}->{$_} = { name => $_ }; $_	} @_;
};

sub validation($$&)
{
	my ($name, $message, $cb) = @_;
	option($name);
	push @{ $context->{options}->{$name}->{validations} }, { message => $message, cb => $cb };
}

sub command(@)
{
	my ($name, $cb) = @_;
	$context->{commands}->{$name} = { cb => $cb };
};

sub mandatory(@) {
	return map {
		assert_option;
		unless ($context->{options}->{$_}->{seen}) {
			$context->{options}->{$_}->{seen} = 1;
			push @{$context->{errors}}, "$_ is mandatory" unless defined($context->{options}->{$_}->{value});
		}
		$_;
	} @_;
};

sub optional(@)
{
	return map {
		assert_option;
		$context->{options}->{$_}->{seen} = 1;
		#$context->{options}->{$_}->{mandatory_ok} = 1;
		$_;
	} @_;
};

sub validate(@)
{
	return map {
		assert_option;
		my $optionref = $context->{options}->{$_};
		for my $v (@{ $optionref->{validations} }) {
			for ($optionref->{value}) {
				my $x = $v->{cb}->();
				error ($v->{message}) unless $v->{cb}->();
			}
		}
		$_;
	} @_;
};

sub scope($@)
{
	my $scopename = shift; 
	return map {
		confess "undefined option $_" unless ($context->{options}->{$_});
		unshift @{$context->{options}->{$_}->{scope}}, $scopename;
		print "ZZ $_\n";
		$_;
	} @_;
};

sub present($)
{
	my ($name) = @_;
	confess "option not defined $name" unless ($context->{options}->{$name});
	return defined($context->{options}->{$name}->{value})
};

sub set($$)
{
	my ($name, $value) = @_;
	confess if ($context->{options}->{$name});
	$context->{options}->{$name} = {source => 'set', value => $value, name => $name };
	return $name;
};

sub error($)
{
	my ($text) = @_;
	push @{$context->{errors}}, $text;
	return;
};
	


1;





