package Dpkg::ErrorHandling;

use Dpkg::Gettext;

use base qw(Exporter);
our @EXPORT_OK = qw( failure syserr error internerr warning
                     warnerror subprocerr );

our $warnable_error = 0;
our $quiet_warnings = 0;
our $progname = "unknown";

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


1;
