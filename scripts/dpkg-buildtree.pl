#!/usr/bin/perl
#
# dpkg-buildtree
#
# Copyright © 2023-2024 Guillem Jover <guillem@debian.org>
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

use Dpkg ();
use Dpkg::Gettext;
use Dpkg::Getopt;
use Dpkg::ErrorHandling;
use Dpkg::BuildTree;

textdomain('dpkg-dev');

sub usage {
    printf g_(
"Usage: %s [<command>]\n" .
    ''), $Dpkg::PROGNAME;
    print_option_sep();

    printf g_(
"Commands:\n" .
    '');
    print_option(g_(
"      clean\n" .
"          Clean dpkg generated artifacts from the build tree.\n" .
    ''));
    print_option(g_(
"      is-rootless\n" .
"          Checks whether the build tree needs root to build.\n" .
    ''));
    print_option(g_(
"      --help\n" .
"          Show this help message.\n" .
    ''));
    print_option(g_(
"      --version\n" .
"          Show the version.\n" .
    ''));
}

my %known_actions = map { $_ => 1 } qw(
    clean
    is-rootless
);
my $action;

while (@ARGV) {
    my $arg = shift @ARGV;
    if (exists $known_actions{$arg}) {
        usageerr(g_('two commands specified: %s and %s'), $1, $action)
            if defined $action;
        $action = $arg;
    } elsif ($arg eq '-?' or $arg eq '--help') {
        usage();
        exit 0;
    } elsif ($arg eq '--version') {
        print_version();
        exit 0;
    } else {
        usageerr(g_("unknown option '%s'"), $arg);
    }
}

usageerr(g_('missing action')) unless $action;

my $bt = Dpkg::BuildTree->new();

if ($action eq 'clean') {
    $bt->clean();
} elsif ($action eq 'is-rootless') {
    exit 1 if $bt->needs_root();
    exit 0;
}
