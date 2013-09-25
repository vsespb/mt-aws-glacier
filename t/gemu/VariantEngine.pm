package VariantEngine;

use strict;
use warnings;
use v5.10;
use Carp;

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
	my ($data, @variants) = @_;
	no warnings 'redefine', 'once';
	local *_get = sub($) {
		$data->{+shift} // confess Dumper $data;
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
			process_recursive({%$data}, @additional, @variants);
		} else {
			if (@vals) {
				for (@vals) {
					process_recursive({%$data, $type => $_}, @variants);
				}
			} else {
				if ($type) {
					process_recursive({%$data}, @variants);
				} else {
					return;
				}
			}
		}
	} else {
		print join(" ", map { "$_=$data->{$_}" } sort keys %$data), "\n";
		process_one($data) unless $ENV{GEMU_TEST_LISTONLY};
	}
}

sub process(&)
{
	my $cb = shift;
	{
		local @variants;
		$cb->();
		process_recursive({}, @variants);
	}
}

1;
