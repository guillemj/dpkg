#!/usr/bin/perl

$dpkglibdir= ".";
$version= '1.3.0'; # This line modified by Makefile

use POSIX;
use POSIX qw(:errno_h :signal_h);

$fileslistfile= 'debian/files';

push(@INC,$dpkglibdir);
require 'controllib.pl';

require 'dpkg-gettext.pl';
textdomain("dpkg-dev");

sub usageversion {
    printf STDERR _g(
"Debian dpkg-distaddfile %s.  Copyright (C) 1996
Ian Jackson.  This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage:
  dpkg-distaddfile <filename> <section> <priority>
Options:  -f<fileslistfile>      write files here instead of debian/files
          -h                     print this message
"), $version;
}

while (@ARGV && $ARGV[0] =~ m/^-/) {
    $_=shift(@ARGV);
    if (m/^-f/) {
        $fileslistfile= $';
    } elsif (m/^-h$/) {
        &usageversion; exit(0);
    } elsif (m/^--$/) {
        last;
    } else {
        &usageerr(sprintf(_g("unknown option %s"), $_));
    }
}

@ARGV==3 || &usageerr(_g("need exactly a filename, section and priority"));
($file,$section,$priority)= @ARGV;

($file =~ m/\s/ || $section =~ m/\s/ || $priority =~ m/\s/) &&
    &error(_g("filename, section and priority may contain no whitespace"));

$fileslistfile="./$fileslistfile" if $fileslistfile =~ m/^\s/;
open(Y,"> $fileslistfile.new") || &syserr(_g("open new files list file"));
chown(@fowner, "$fileslistfile.new") 
		|| &syserr(_g("chown new files list file"));
if (open(X,"< $fileslistfile")) {
    while (<X>) {
        s/\n$//;
        next if m/^(\S+) / && $1 eq $file;
        print(Y "$_\n") || &syserr(_g("copy old entry to new files list file"));
    }
} elsif ($! != ENOENT) {
    &syserr(_g("read old files list file"));
}
print(Y "$file $section $priority\n")
    || &syserr(_g("write new entry to new files list file"));
close(Y) || &syserr(_g("close new files list file"));
rename("$fileslistfile.new",$fileslistfile) || &syserr(gettetx("install new files list file"));
