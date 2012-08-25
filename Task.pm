package Task;

use strict;
use warnings;


sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    bless $self, $class;
    $self->{action}||die;
    defined($self->{id})||die;
    $self->{data}||die;
    $self->{result}={};
    return $self;
}

	
1;