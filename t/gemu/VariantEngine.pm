package VariantEngine;

use strict;
use warnings;
use v5.10;
use Carp;
use Data::Dumper;

require Exporter;
use base qw/Exporter/;

our @EXPORT = qw/get before add process/;


our @variants;

sub get($) { &_get };
sub _get($) { confess "Unimplemented"; };
sub before($) { confess "Unimplemented"; };
sub _add
{
	__add(\@variants, @_);

}
sub __add
{
	my $variants = shift;
	if (@_ == 1 ) {
		push @$variants, shift;
	} else {
		my @a = @_;
		push @$variants, sub { @a };
	}
	return;
}
sub add
{
	&_add;
}


sub process_recursive
{
	my ($exec_cb, $data, @variants) = @_;
	no warnings 'redefine', 'once';
	local *_get = sub($) {
		my $x = shift;
		$data->{$x} // confess Dumper [$x, $data];
	};
	#local *before = sub($) {
	#	confess "use before $_[0]" if defined $data->{$_[0]};
	#};
	local *main::AUTOLOAD = sub {
		use vars qw/$AUTOLOAD/;
		$AUTOLOAD =~ s/^.*:://;
		_get("$AUTOLOAD");
	};
	if (@variants) {
		my $v = shift @variants;

		my @additional;
		local *_add = sub {
			__add(\@additional, @_);
		};

		my ($type, @vals) = $v->($data);

		if (@additional) {
			process_recursive($exec_cb, {%$data}, @additional, @variants);
		} else {
			if (@vals) {
				for (@vals) {
					process_recursive($exec_cb, {%$data, $type => $_}, @variants);
				}
			} else {
				if ($type) {
					process_recursive($exec_cb, {%$data}, @variants);
				} else {
					return;
				}
			}
		}
	} else {
		print join(" ", map { "$_=$data->{$_}" } sort keys %$data), "\n";
		$exec_cb->($data) unless $ENV{GEMU_TEST_LISTONLY};
	}
}

sub process(&&)
{
	my ($cb, $exec_cb) = @_;
	{
		local @variants;
		$cb->();
		process_recursive($exec_cb, {}, @variants);
	}
}

1;
