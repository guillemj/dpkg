#!/usr/bin/perl --
# This script is only supposed to be called by dpkg-split.
# Its arguments are:
#  <sourcefile> <partsize> <prefix> <totalsize> <partsizeallow> <msdostruncyesno>
# Stdin is also redirected from the source archive by dpkg-split.

# Copyright (C) 1995 Ian Jackson <ijackson@nyx.cs.du.edu>
#
#   This is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as
#   published by the Free Software Foundation; either version 2,
#   or (at your option) any later version.
#
#   This is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with dpkg; if not, write to the Free Software
#   Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

@ARGV == 6 || die "mksplit: bad invocation\n";

($sourcefile,$partsize,$prefix,$orgsize,$partsizeallow,$msdos) = @ARGV;

sub output {
    $!=0; $rv= `$_[0]`; $? && die "mksplit $_[0]: $! $?\n";
    $rv =~ s/\n$//; $rv =~ s/\s+$//; $rv =~ s/^\s+//;
    $rv;
}

$myversion='2.1';
$csum= &output("md5sum <\"$sourcefile\"");
$package= &output("dpkg-deb --field \"$sourcefile\" Package");
$version= &output("dpkg-deb --field \"$sourcefile\" Version");
$revision= &output("dpkg-deb --field \"$sourcefile\" Package_Revision");
$version.= "-$revision" if length($revision);
$nparts=int(($orgsize+$partsize-1)/$partsize);
$startat=0;
$showpartnum=1;

$|=1;
print("Splitting package $package into $nparts parts: ");

$msdos= ($msdos eq 'yes');
if ($msdos) {
    $prefixdir= $prefix; $prefixdir =~ s:(/?)/*[^/]+$:$1:;
    $cleanprefix= $prefix; $cleanprefix =~ s:^.*/+::;
    $cleanprefix =~ y/A-Za-z0-9+/a-za-z0-9x/;
    $cleanprefix =~ y/a-z0-9//cd;
}

sub add {
    $data .=
        sprintf("%-16s%-12d0     0     100644  %-10d%c\n%s%s",
                $_[0], time, length($_[1]), 0140, $_[1],
                (length($_[1]) & 1) ? "\n" : "");
}                 

while ($startat < $orgsize) {
    $dsp= "$myversion\n$package\n$version\n$csum\n$orgsize\n$partsize\n".
          "$showpartnum/$nparts\n";
    defined($thispartreallen= read(STDIN,$pd,$partsize)) || die "mksplit: read: $!\n";
    $data= "!<arch>\n";
    print("$showpartnum ");
    &add('debian-split',$dsp);
    &add("data.$showpartnum",$pd);
    if ($thispartreallen > $partsizeallow) {
        die "Header is too long, making part too long.  Your package name or version\n".
            "numbers must be extraordinarily long, or something.  Giving up.\n";
    }
    if ($msdos) {
        $basename= "${showpartnum}of$nparts.$cleanprefix";
        $basename= substr($basename,0,9);
        $basename =~ s/^([^.]*)\.(.*)$/$2$1/;
        $basename= "$prefixdir$basename";
    } else {
        $basename= "$prefix.${showpartnum}of$nparts";
    }
    open(O,"> $basename.deb") || die("mksplit: open $basename.deb: $!\n");
    print(O $data) || die("mksplit: write $basename.deb: $!\n");
    close(O) || die("mksplit: close $basename.deb: $!\n");
    $startat += $partsize;
    $showpartnum++;
}
print("done\n");

exit(0);
