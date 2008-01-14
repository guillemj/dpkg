#!/usr/bin/perl

use strict;
use warnings;

use English;
use POSIX;
use POSIX qw(:errno_h);
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(warning error syserr subprocerr usageerr);
use Dpkg::Changelog qw(parse_changelog);

textdomain("dpkg-dev");

my %options;

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

while (@ARGV) {
    last unless $ARGV[0] =~ m/^-/;
    $_ = shift(@ARGV);
    if (m/^-L(.+)$/) {
	$options{"libdir"} = $1;
    } elsif (m/^-F([0-9a-z]+)$/) {
	$options{"changelogformat"} = $1;
    } elsif (m/^-l(.+)$/) {
	$options{"file"} = $1;
    } elsif (m/^--$/) {
	last;
    } elsif (m/^-([cfnostuv])(.*)$/) {
	if (($1 eq "c") or ($1 eq "n")) {
	    $options{"count"} = $2;
	} elsif ($1 eq "f") {
	    $options{"from"} = $2;
	} elsif ($1 eq "o") {
	    $options{"offset"} = $2;
	} elsif (($1 eq "s") or ($1 eq "v")) {
	    $options{"since"} = $2;
	} elsif ($1 eq "t") {
	    $options{"to"} = $2;
	} elsif ($1 eq "u") {
	    $options{"until"} = $2;
	}
    } elsif (m/^--(count|file|format|from|offset|since|to|until)(.*)$/) {
	if ($2) {
	    $options{$1} = $2;
	} else {
	    $options{$1} = shift(@ARGV);
	}
    } elsif (m/^--all$/) {
	$options{"all"} = undef;
    } elsif (m/^-(h|-help)$/) {
	usage(); exit(0);
    } elsif (m/^--version$/) {
	version(); exit(0);
    } else {
	usageerr(_g("unknown option \`%s'"), $_);
    }
}

@ARGV && usageerr(_g("%s takes no non-option arguments"), $progname);

my $count = 0;
my @fields = parse_changelog(%options);
foreach my $f (@fields) {
    print "\n" if $count++;
    print tied(%$f)->dump();
}

