#!/usr/bin/perl
#
# Copyright © 1995-1998 Ian Jackson <ijackson@chiark.greenend.org.uk>
# Copyright © 1998 Heiko Schlittermann <hs@schlittermann.de>
# Copyright © 2009 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2009-2025 Guillem Jover <guillem@debian.org>
#
# This is free software; you can redistribute it and/or modify
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
use Dselect::Method::Media;

eval q{
    use Dpkg::Version;
};
if ($@) {
    warn "Missing Dpkg modules required by the Media access method.\n\n";
    exit 1;
}

my $vardir = $ARGV[0];
my $method = $ARGV[1];
my $option = $ARGV[2];

chdir "$vardir/methods/$method";

my $conf = Dselect::Method::Config->new();

$conf->load("./shvar.$option");

my $p_blockdev = $conf->get('p_blockdev');
my $p_mountpoint = $conf->get('p_mountpoint');
my $p_hierbase = $conf->get('p_hierbase');

my $umount;

my $exit = 1;

sub do_umount {
    if (length $umount) {
        system 'umount', $umount;
    }
}

sub do_mount {
    my $opts = 'nosuid,nodev';
    if (! -b $p_blockdev) {
        $opts .= ',loop';
    }

    if (length $p_blockdev) {
        $umount = $p_mountpoint;
        system qw(mount -rt iso9660 -o), $opts, $p_blockdev, $p_mountpoint;
    }
}

do_mount();

my $predep = "$vardir/predep-package";
my $binaryprefix = "$p_mountpoint$p_hierbase";

while (1) {
    my $package;
    my $version;
    my @filename;
    my $medium;

    my $thisdisk = get_disk_label($p_mountpoint, $p_hierbase);

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
        if (m{^X-Medium:\s+(.*)\s*}) {
            $medium = $1;
        }
        @filename = split / / if s/^Filename: //i;
    }
    close $predep_fh;
    die 'internal error - no package' if length($package) == 0;
    die 'internal error - no filename' if not @filename;
    if ($medium && ($medium ne $thisdisk)) {
        print <<"INFO";

This is
    $thisdisk
However, $package is expected on disc:
    $medium
Please change the discs and press <RETURN>.

INFO
        exit(1);
    }

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
                     length($binaryprefix) ? $binaryprefix : '.',
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
    exec('dpkg', '-iB', '--', @invoke);
    die "failed to exec dpkg: $!\n";
}

$SIG{INT} = sub {
    chdir $vardir;
    unlink <tmp/*>;
    exit 1;
};
$| = 1;

my $line;
my $AVAIL = "$vardir/methods/media/available";
my $STATUS = "$vardir/status";
my (%installed, %filename, %medium);

print 'Get currently installed package versions...';
open my $status_fh, '<', $STATUS
    or die "cannot open $STATUS: $!\n";
$line = 0;
{
    local $/ = q{};

    while (<$status_fh>) {
        if ($line++ % 20 == 0) {
            print q{.};
        }
        s/\n\s+/ /g;
        my %status = (
            q{},
            split /^(\S*?):\s*/m,
        );
        foreach my $field (keys %status) {
            chomp $status{$field};
            $status{$field} =~ s/^\s*(.*?)\s*$/$1/;
        }
        my @pstat = split(/ /, $status{Status});
        next unless ($pstat[0] eq 'install');
        if ($pstat[2] eq 'config-files' || $pstat[2] eq 'not-installed') {
            $installed{$status{Package}} = '0.0';
        } else {
            $installed{$status{Package}} = $status{Version} || q{};
        }
    }
}
close $status_fh;
print "\nGot ", scalar keys %installed, " installed/pending packages\n";

print 'Scanning available packages...';
$line = 0;
open my $avail_fh, '<', $AVAIL
    or die("Cannot open $AVAIL: $!\n");
{
    local $/ = q{};
    while (<$avail_fh>) {
        my $updated;

        if ($line++ % 20 == 0) {
            print q{.};
        }

        s/\n\s+/ /g;
        my %avail = (
            q{},
            split /^(\S*?):\s*/m,
        );
        foreach my $field (keys %avail) {
            chomp $avail{$field};
            $avail{$field} =~ s/^\s*(.*?)\s*$/$1/;
        }

        next unless defined $installed{$avail{Package}};

        $updated = version_compare($avail{Version},
                                   $installed{$avail{Package}}) > 0;
#       print "$avail{Package}(" . ($updated ? "+" : "=") . ") ";
        next unless $updated;

        $filename{$avail{Package}} = $avail{Filename};

        next unless defined $avail{'X-Medium'};
        $medium{$avail{'X-Medium'}} //= [];
        push @{$medium{$avail{'X-Medium'}}}, $avail{Package};
    }
}
close $avail_fh;
print "\n";

my $ouch;

my @media = sort keys %medium;
if (@media) {
    print "You will need the following distribution disc(s):\n",
          join(q{, }, @media), "\n";
}

foreach my $need (@media) {
    my $disk = get_disk_label($p_mountpoint, $p_hierbase);

    print "Processing disc\n   $need\n";

    while ($disk ne $need) {
        print "Wrong disc.  This is disc\n    $disk\n";
        print "However, the needed disc is\n    $need\n";
        print "Please change the discs and press <RETURN>\n";
        do_umount();
        <STDIN>;
        do_mount();
        if ($?) {
            warn "cannot mount $p_mountpoint\n";
        }
    } continue {
        $disk = get_disk_label($p_mountpoint, $p_hierbase);
    }

    if (! -d 'tmp') {
        mkdir 'tmp', 0o755
            or die("Cannot mkdir tmp: $!\n");
    }
    unlink <tmp/*>;

    print "creating symlinks...\n";
    foreach my $pkgname (@{$medium{$need}}) {
        my $basename;

        ($basename = $filename{$pkgname}) =~ s/.*\///;
        symlink "$p_mountpoint/$p_hierbase/$filename{$pkgname}", "tmp/$basename";
    }
    chdir 'tmp' or die "cannot chdir to tmp: $!\n";
    system 'dpkg', '-iGROEB', q{.};
    unlink <*>;
    chdir q{..};

    if ($?) {
        print "\nThe dpkg run produced errors. Please state whether to\n",
              'continue with the next media disc. [Y/n]: ';
        my $answer = <STDIN>;
        exit 1 if $answer =~ /^n/i;
        $ouch = $?;
    }
}

exit $ouch;


print 'Installation OK. Hit RETURN.';
<STDIN>;

$exit = 0;

END {
    do_umount();
    exit $exit;
}
