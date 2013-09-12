package App::MtAws::QueueJob;

use strict;
use warnings;

use Carp;
use base 'Exporter';

use constant JOB_RETRY => 39201;
use constant JOB_OK => 39202;
use constant JOB_WAIT => 39203;
use constant JOB_DONE => 39204;

our @EXPORT = qw/JOB_RETRY JOB_OK JOB_WAIT JOB_DONE state task/;

sub _is_code
{
	my $c = shift;
	$c =~ /\A\d+\z/ && grep { $_ == $c } (JOB_RETRY, JOB_OK, JOB_WAIT, JOB_DONE);
}


sub state($)
{
	{ MT_RESULT => 1, state => shift }
}

sub task(@)
{
	my $cb = pop;
	my $task_action = shift;
	confess unless $cb && ref($cb) eq ref(sub {});
	my @args = @_;
	return { MT_RESULT => 1, code => JOB_OK, task_action => $task_action, task_cb => $cb, task_args => \@args };
}

# return WAIT, "my_task", 1, 2, 3, sub { ... }
sub parse_result
{
	my $res = {};
	for (@_) {
		if (ref($_) eq ref({})) {
			confess "unknown hash ref" unless ($_->{MT_RESULT});
			confess "double code" if defined($res->{code}) && defined($_->{code});
			%$res = (%$res, %$_);
		} elsif (ref($_) eq ref("")) {
			confess "code already exists" if defined($res->{code});
			$res->{code} = $_;
		}
		$res->{MT_RESULT} = 1;
	}
	confess "no data" unless $res->{MT_RESULT};
	confess "no code" unless defined($res->{code});
	confess "bad code" unless _is_code($res->{code});
	if ($res->{code} == JOB_OK) {
		confess "no action" unless defined($res->{task_action});
		confess "no cb" unless defined($res->{task_cb});
		confess "no args" unless defined($res->{task_args});
	}
	if ($res->{code} != JOB_OK) {
		confess "unexpected action" if defined($res->{task_action});
		confess "unexpected cb" if defined($res->{task_cb});
		confess "unexpected args" if defined($res->{task_args});
	}
	$res;
}

sub new
{
	my ($class, %args) = @_;
	my $self = \%args;
	bless $self, $class;
	$self->{_state} = 'default';
	$self->{_jobs} = [];
	return $self;
}

sub enter { $_[0]->{_state} = $_[1]; JOB_RETRY }

sub push
{
	my ($self, $job, $cb) = @_;
	push @{ $self->{_jobs} }, { job => $job, cb => $cb };
	JOB_RETRY;
}

sub next
{
	my ($self) = @_;

	while () {
		if ( @{ $self->{_jobs} } ) {
			my $res = $self->{_jobs}->[-1]->{job}->next();
			confess unless $res->{MT_RESULT};
			if ($res->{code} == JOB_DONE) {
				my $j = pop @{ $self->{_jobs} };
				$j->{cb}->($j->{job}) if $j->{cb};
			} else {
				return $res;
			}
		} else {
			my $method = "on_$self->{_state}";
			my $res = parse_result($self->$method());
			$self->enter($res->{state}) if defined($res->{state});
			redo if $res->{code} == JOB_RETRY;
			return $res;
		}
	}
}

sub on_wait
{
	JOB_WAIT
}

sub on_done
{
	JOB_DONE
}

sub on_die
{
	confess;
}

1;
