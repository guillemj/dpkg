#!/usr/bin/perl

$dpkglibdir= ".";
$version= '1.3.0'; # This line modified by Makefile

use POSIX;
use POSIX qw(:errno_h :signal_h);

$fileslistfile= 'debian/files';

push(@INC,$dpkglibdir);
require 'controllib.pl';

sub usageversion {
    print STDERR
"Debian dpkg-distaddfile $version.  Copyright (C) 1996
Ian Jackson.  This is free software; see the GNU General Public Licence
version 2 or later for copying conditions.  There is NO warranty.

Usage:
  dpkg-distaddfile <filename> <section> <priority>
Options:  -f<fileslistfile>      write files here instead of debian/files
          -h                     print this message
";
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
        &usageerr("unknown option $_");
    }
}

@ARGV==3 || &usageerr("need exactly a filename, section and priority");
($file,$section,$priority)= @ARGV;

($file =~ m/\s/ || $section =~ m/\s/ || $priority =~ m/\s/) &&
    &error("filename, section and priority may contain no whitespace");

$fileslistfile="./$fileslistfile" if $fileslistfile =~ m/^\s/;
open(Y,"> $fileslistfile.new") || &syserr("open new files list file");
chown(@fowner, "$fileslistfile.new") 
		|| &syserr("chown new files list file");
if (open(X,"< $fileslistfile")) {
    while (<X>) {
        s/\n$//;
        next if m/^(\S+) / && $1 eq $file;
        print(Y "$_\n") || &syserr("copy old entry to new files list file");
    }
} elsif ($! != ENOENT) {
    &syserr("read old files list file");
}
print(Y "$file $section $priority\n")
    || &syserr("write new entry to new files list file");
close(Y) || &syserr("close new files list file");
rename("$fileslistfile.new",$fileslistfile) || &syserr("install new files list file");
