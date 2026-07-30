#!/usr/bin/perl
#
# dpkg-distaddfile
#
# Copyright © 1996 Ian Jackson
# Copyright © 2006-2008,2010,2012-2014 Guillem Jover <guillem@debian.org>
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

use Fcntl;

use Dpkg ();
use Dpkg::Gettext;
use Dpkg::Getopt;
use Dpkg::ErrorHandling;
use Dpkg::Lock;
use Dpkg::Dist::Files;

textdomain('dpkg-dev');

my $fileslistfile = 'debian/files';

sub usage {
    printf g_(
"Usage: %s [<option>...] <filename> <section> <priority>\n" .
    ''), $Dpkg::PROGNAME;
    print_option_sep();

    printf g_(
"Options:\n" .
    '');
    print_option(g_(
"  -f<files-list-file>\n" .
"          Write files here instead of debian/files.\n" .
    ''));
    print_option(g_(
"  -?, --help\n" .
"          Show this help message.\n" .
    ''));
    print_option(g_(
"      --version\n" .
"          Show the version.\n" .
    ''));
}

while (@ARGV && $ARGV[0] =~ m/^-/) {
    $_ = shift @ARGV;
    if (m/^-f/p) {
        $fileslistfile = ${^POSTMATCH};
    } elsif (m/^-(?:\?|-help)$/) {
        usage();
        exit(0);
    } elsif (m/^--version$/) {
        print_version();
        exit(0);
    } elsif (m/^--$/) {
        last;
    } else {
        usageerr(g_("unknown option '%s'"), $_);
    }
}
usageerr(g_('need exactly a filename, section and priority')) if @ARGV != 3;

my ($filename, $section, $priority) = @ARGV;

($filename =~ m/\s/ || $section =~ m/\s/ || $priority =~ m/\s/) &&
    error(g_('filename, section and priority may contain no whitespace'));

# Obtain a lock on debian/control to avoid simultaneous updates
# of debian/files when parallel building is in use.
my $lockfh;
my $lockfile = 'debian/control';
sysopen($lockfh, $lockfile, O_WRONLY)
    or syserr(g_('cannot write %s'), $lockfile);
file_lock($lockfh, $lockfile);

my $dist = Dpkg::Dist::Files->new();
$dist->load($fileslistfile) if -e $fileslistfile;
$dist->add_file($filename, $section, $priority);
$dist->save("$fileslistfile.new");

rename("$fileslistfile.new", $fileslistfile)
    or syserr(g_('cannot install new files list file'));

# Release the lock.
close($lockfh) or syserr(g_('cannot close %s'), $lockfile);
