#!/usr/bin/perl

use strict;
use warnings;

use POSIX;
use POSIX qw(:errno_h :signal_h);
use Dpkg;
use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(error syserr usageerr);

textdomain("dpkg-dev");

my $fileslistfile = 'debian/files';


sub version {
    printf _g("Debian %s version %s.\n"), $progname, $version;

    printf _g("
Copyright (C) 1996 Ian Jackson.");

    printf _g("
This is free software; see the GNU General Public Licence version 2 or
later for copying conditions. There is NO warranty.
");
}

sub usage {
    printf _g(
"Usage: %s [<option>...] <filename> <section> <priority>

Options:
  -f<fileslistfile>        write files here instead of debian/files.
  -h, --help               show this help message.
      --version            show the version.
"), $progname;
}

while (@ARGV && $ARGV[0] =~ m/^-/) {
    $_=shift(@ARGV);
    if (m/^-f/) {
        $fileslistfile= $';
    } elsif (m/^-(h|-help)$/) {
        &usage; exit(0);
    } elsif (m/^--version$/) {
        &version; exit(0);
    } elsif (m/^--$/) {
        last;
    } else {
        usageerr(_g("unknown option \`%s'"), $_);
    }
}

@ARGV==3 || &usageerr(_g("need exactly a filename, section and priority"));
my ($file, $section, $priority) = @ARGV;

($file =~ m/\s/ || $section =~ m/\s/ || $priority =~ m/\s/) &&
    &error(_g("filename, section and priority may contain no whitespace"));

$fileslistfile="./$fileslistfile" if $fileslistfile =~ m/^\s/;
open(Y,"> $fileslistfile.new") || &syserr(_g("open new files list file"));
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
