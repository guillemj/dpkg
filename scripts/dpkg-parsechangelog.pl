#!/usr/bin/perl

$dpkglibdir= "/usr/lib/dpkg";
$version= '1.3.0'; # This line modified by Makefile

$format='debian';
$changelogfile='debian/changelog';
@parserpath= ("/usr/local/lib/dpkg/parsechangelog",
              "$dpkglibdir/parsechangelog");

use POSIX;
use POSIX qw(:errno_h);

push(@INC,$dpkglibdir);
require 'controllib.pl';

sub usageversion {
    print STDERR
"Debian dpkg-parsechangelog $version.
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2001 Wichert Akkerman
This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage: dpkg-parsechangelog [<option> ...]
Options:  -l<changelogfile>      get per-version info from this file
          -v<sinceversion>       include all changes later than version
          -F<changelogformat>    force change log format
          -L<libdir>             look for change log parsers in <libdir>
          -h                     print this message
";
}

@ap=();
while (@ARGV) {
    last unless $ARGV[0] =~ m/^-/;
    $_= shift(@ARGV);
    if (m/^-L/ && length($_)>2) { $libdir=$'; next; }
    if (m/^-F([0-9a-z]+)$/) { $force=1; $format=$1; next; }
    if (m/^-l/ && length($_)>2) { $changelogfile=$'; next; }
    push(@ap,$_);
    m/^--$/ && last;
    m/^-v/ && next;
    if (m/^-h$/) { &usageversion; exit(0); }
    &usageerr("unknown option \`$_'");
}

@ARGV && &usageerr("$progname takes no non-option arguments");
$changelogfile= "./$changelogfile" if $changelogfile =~ m/^\s/;

if (not $force and $changelogfile ne "-") {
    open(STDIN,"< $changelogfile") ||
        &error("cannot open $changelogfile to find format: $!");
    open(P,"tail -n 40 |") || die "cannot fork: $!\n";
    while(<P>) {
        next unless m/\schangelog-format:\s+([0-9a-z]+)\W/;
        $format=$1;
    }
    close(P); $? && &subprocerr("tail of $changelogfile");
}


for $pd (@parserpath) {
    $pa= "$pd/$format";
    if (!stat("$pa")) {
        $! == ENOENT || &syserr("failed to check for format parser $pa");
    } elsif (!-x _) {
        &warn("format parser $pa not executable");
    } else {
        $pf= $pa;
	last;
    }
}
        
defined($pf) || &error("format $pa unknown");

if ($changelogfile ne "-") {
    open(STDIN,"< $changelogfile") || die "cannot open $changelogfile: $!\n";
}
exec($pf,@ap); die "cannot exec format parser: $!\n";

