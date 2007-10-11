package Dpkg::ErrorHandling;

use Dpkg;
use Dpkg::Gettext;

use base qw(Exporter);
our @EXPORT_OK = qw(warning warnerror error failure unknown syserr internerr
                    subprocerr usageerr $warnable_error $quiet_warnings);

our $warnable_error = 1;
our $quiet_warnings = 0;

sub failure { die sprintf(_g("%s: failure: %s"), $progname, $_[0])."\n"; }
sub syserr { die sprintf(_g("%s: failure: %s: %s"), $progname, $_[0], $!)."\n"; }
sub error { die sprintf(_g("%s: error: %s"), $progname, $_[0])."\n"; }
sub internerr { die sprintf(_g("%s: internal error: %s"), $progname, $_[0])."\n"; }

sub warning
{
    if (!$quiet_warnings) {
	warn sprintf(_g("%s: warning: %s"), $progname, $_[0])."\n";
    }
}

sub warnerror
{
    if ($warnable_error) {
	warning(@_);
    } else {
	error(@_);
    }
}

sub unknown {
    my $field = $_;
    warning(sprintf(_g("unknown information field '%s' in input data in %s"),
                    $field, $_[0]));
}

sub subprocerr {
    my ($p) = @_;
    require POSIX;
    if (POSIX::WIFEXITED($?)) {
	die sprintf(_g("%s: failure: %s gave error exit status %s"),
		    $progname, $p, POSIX::WEXITSTATUS($?))."\n";
    } elsif (POSIX::WIFSIGNALED($?)) {
	die sprintf(_g("%s: failure: %s died from signal %s"),
		    $progname, $p, POSIX::WTERMSIG($?))."\n";
    } else {
	die sprintf(_g("%s: failure: %s failed with unknown exit code %d"),
		    $progname, $p, $?)."\n";
    }
}

sub usageerr
{
    printf(STDERR "%s: %s\n\n", $progname, "@_");
    # XXX: access to main namespace
    main::usage();
    exit(2);
}

1;
