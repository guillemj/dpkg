#!/usr/bin/perl
#
# Copyright © 1996 Ian Jackson <ijackson@chiark.greenend.org.uk>
# Copyright © 2000 Adam Heath <doogie@debian.org>
# Copyright © 2009-2025 Guillem Jover <guillem@debian.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use v5.36;

use Dselect::Method::Config;

my $vardir = $ARGV[0];
my $method = $ARGV[1];
my $option = $ARGV[2];

chdir "$vardir/methods/file";

my $conf = Dselect::Method::Config->new();

$conf->load("./shvar.$option");

my $exit = 1;

my $predep = "$vardir/predep-package";
my $binaryprefix = $conf->get('p_mountpoint') . $conf->get('p_main_binary');
$binaryprefix =~ s{/*$}{/} if length($binaryprefix);

while (1) {
    my $package;
    my $version;
    my @filename;

    system "dpkg --admindir '$vardir' --predep-package >'$predep'";
    my $rc = $? >> 8;
    last if $rc == 1;
    die if $rc != 0;

    open my $predep_fh, '<', $predep
        or die "cannot open $predep: $!\n";
    while (<$predep_fh>) {
        s/\s*\n$//;
        $package = $_ if s/^Package: //i;
        $version = $_ if s{^Version: }{}i;
        @filename = split / / if s/^Filename: //i;
    }
    close $predep_fh;
    die 'internal error - no package' if length($package) == 0;
    die 'internal error - no filename' if not @filename;

    my @invoke = ();
    $| = 1;
    foreach my $i (0 .. $#filename) {
        my $ppart = $i + 1;
        my $print;
        my $invoke;
        my $base;

        print "Looking for part $ppart of $package ... ";
        if (-f "$binaryprefix$filename[$i]") {
            $print = $filename[$i];
            $invoke = "$binaryprefix$filename[$i]";
        } else {
            $base = $filename[$i];
            $base =~ s{.*/}{};
            my $c = open my $find_fh, '-|';
            if (not defined $c) {
                die "failed to fork for find: $!\n";
            }
            if (! $c) {
                exec('find', '-L',
                     length($binaryprefix) ?
                     $binaryprefix : q{.},
                     '-name', $base);
                die "failed to exec find: $!\n";
            }
            while (chop($invoke = <$find_fh>)) {
                last if -f $invoke;
            }
            close $find_fh;
            $print = $invoke;
            my $printprefix = substr $print, 0, length $binaryprefix + 1;
            if ($printprefix eq "$binaryprefix/") {
                $print = substr $print, length $binaryprefix;
            }
        }
        if (! length($invoke)) {
            warn <<"WARN";

Cannot find the appropriate file(s) anywhere needed to install or upgrade
package $package. Expecting version $version or later, as listed in the
Packages file.

Perhaps the package was downloaded with an unexpected name? In any case,
you must find the file(s) and then either place it with the correct
filename(s) (as listed in the Packages file or in $vardir/available)
and rerun the installation, or upgrade the package by using
"dpkg --install --auto-deconfigure" by hand.

WARN
            exit(1);
        }
        print "$print\n";
        push(@invoke, $invoke);
    }

    print "Running dpkg -iB for $package ...\n";
    exec('dpkg', '--admindir', $vardir, '-iB', '--', @invoke);
    die "failed to exec dpkg: $!\n";
}

foreach my $f (qw(main ctb nf lcl)) {
    my $this_binary = $conf->get("p_${f}_binary");
    next if length $this_binary == 0;

    my @cmd = (
        'dpkg',
        '--admindir', $vardir,
        '-iGROEB',
        $conf->get('p_mountpoint') . $this_binary,
    );

    print "Running @cmd\n";
    system(@cmd) == 0
        or die;
}

print 'Installation OK. Hit RETURN.';
<STDIN>;

$exit = 0;

END {
    exit $exit;
}
