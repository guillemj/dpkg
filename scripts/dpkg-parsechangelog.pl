#!/usr/bin/perl

use strict;
use warnings;

use English;
use POSIX;
use POSIX qw(:errno_h);
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning error syserr subprocerr usageerr);

textdomain("dpkg-dev");

my $format ='debian';
my $changelogfile = 'debian/changelog';
my @parserpath = ("/usr/local/lib/dpkg/parsechangelog",
                  "$dpkglibdir/parsechangelog");

my $libdir;
my $force;


sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson.
Copyright (C) 2001 Wichert Akkerman");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option> ...]

Options:
  -l<changelogfile>        get per-version info from this file.
  -F<changelogformat>      force change log format.
  -L<libdir>               look for change log parsers in <libdir>.
  -h, --help               show this help message.
      --version            show the version.

parser options:
    --format <outputformat>     see man page for list of available
                                output formats, defaults to 'dpkg'
                                for compatibility with dpkg-dev
    --since, -s, -v <version>   include all changes later than version
    --until, -u <version>       include all changes earlier than version
    --from, -f <version>        include all changes equal or later
                                than version
    --to, -t <version>          include all changes up to or equal
                                than version
    --count, -c, -n <number>    include <number> entries from the top
                                (or the tail if <number> is lower than 0)
    --offset, -o <number>       change the starting point for --count,
                                counted from the top (or the tail if
                                <number> is lower than 0)
    --all                       include all changes
"), $progname;
}

my @ap = ();
while (@ARGV) {
    last unless $ARGV[0] =~ m/^-/;
    $_= shift(@ARGV);
    if (m/^-L/ && length($_)>2) { $libdir=$POSTMATCH; next; }
    if (m/^-F([0-9a-z]+)$/) { $force=1; $format=$1; next; }
    push(@ap,$_);
    if (m/^-l/ && length($_)>2) { $changelogfile=$POSTMATCH; next; }
    m/^--$/ && last;
    m/^-[cfnostuv]/ && next;
    m/^--(all|count|file|format|from|offset|since|to|until)(.*)$/ && do {
	push(@ap, shift(@ARGV)) unless $2;
	next;
    };
    if (m/^-(h|-help)$/) { &usage; exit(0); }
    if (m/^--version$/) { &version; exit(0); }
    &usageerr(_g("unknown option \`%s'"), $_);
}

@ARGV && usageerr(_g("%s takes no non-option arguments"), $progname);

if (not $force and $changelogfile ne "-") {
    open(STDIN,"<", $changelogfile) ||
	syserr(_g("cannot open %s to find format"), $changelogfile);
    open(P,"-|","tail","-n",40) || syserr(_g("cannot fork"));
    while(<P>) {
        next unless m/\schangelog-format:\s+([0-9a-z]+)\W/;
        $format=$1;
    }
    close(P);
    $? && subprocerr(_g("tail of %s"), $changelogfile);
}

my ($pa, $pf);

unshift(@parserpath, $libdir) if $libdir;
for my $pd (@parserpath) {
    $pa= "$pd/$format";
    if (!stat("$pa")) {
        $! == ENOENT || syserr(_g("failed to check for format parser %s"), $pa);
    } elsif (!-x _) {
	warning(_g("format parser %s not executable"), $pa);
    } else {
        $pf= $pa;
	last;
    }
}

defined($pf) || error(_g("format %s unknown"), $pa);

if ($changelogfile ne "-") {
    open(STDIN,"<", $changelogfile)
	|| syserr(_g("cannot open %s: %s"), $changelogfile);
}
exec($pf,@ap) || syserr(_g("cannot exec format parser: %s"));

