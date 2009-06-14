package Dpkg::ErrorHandling;

use Dpkg;
use Dpkg::Gettext;

use base qw(Exporter);
our @EXPORT = qw(info warning error errormsg
                 syserr internerr subprocerr usageerr syntaxerr);
our @EXPORT_OK = qw(report unknown $quiet_warnings);

our $quiet_warnings = 0;

sub report(@)
{
    my ($type, $msg) = (shift, shift);

    $msg = sprintf($msg, @_) if (@_);
    return "$progname: $type: $msg\n";
}

sub info($;@)
{
    print report(_g("info"), @_) if (!$quiet_warnings);
}

sub warning($;@)
{
    warn report(_g("warning"), @_) if (!$quiet_warnings);
}

sub syserr($;@)
{
    my $msg = shift;
    die report(_g("error"), "$msg: $!", @_);
}

sub error($;@)
{
    die report(_g("error"), @_);
}

sub errormsg($;@)
{
    print STDERR report(_g("error"), @_);
}

sub internerr($;@)
{
    die report(_g("internal error"), @_);
}

sub unknown($)
{
    # XXX: implicit argument
    my $field = $_;
    warning(_g("unknown information field '%s' in input data in %s"),
            $field, $_[0]);
}

sub subprocerr(@)
{
    my ($p) = (shift);

    $p = sprintf($p, @_) if (@_);

    require POSIX;

    if (POSIX::WIFEXITED($?)) {
	error(_g("%s gave error exit status %s"), $p, POSIX::WEXITSTATUS($?));
    } elsif (POSIX::WIFSIGNALED($?)) {
	error(_g("%s died from signal %s"), $p, POSIX::WTERMSIG($?));
    } else {
	error(_g("%s failed with unknown exit code %d"), $p, $?);
    }
}

sub usageerr(@)
{
    my ($msg) = (shift);

    $msg = sprintf($msg, @_) if (@_);
    warn "$progname: $msg\n\n";
    # XXX: access to main namespace
    main::usage();
    exit(2);
}

sub syntaxerr {
    my ($file, $msg) = @_;
    error(_g("syntax error in %s at line %d: %s"), $file, $., $msg);
}

1;
