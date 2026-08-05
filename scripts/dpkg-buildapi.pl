#!/usr/bin/perl
#
# dpkg-buildapi
#
# Copyright © 2022 Guillem Jover <guillem@debian.org>
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
use Dpkg::BuildAPI qw(get_build_api);
use Dpkg::Control::Info;

textdomain('dpkg-dev');

sub usage
{
    printf g_(
"Usage: %s [<option>...] [<command>]\n" .
    ''), $Dpkg::PROGNAME;
    print_option_sep();

    printf g_(
"Commands:\n" .
"  -?, --help\n" .
"          Show this help message.\n" .
"      --version\n" .
"          Show the version.\n" .
    '');
    print_option_sep();

    printf g_(
"Options:\n" .
"  -c<control-file>\n" .
"          Get control info from this file.\n" .
    '');
}

my $controlfile = 'debian/control';

while (@ARGV) {
    $_ = shift(@ARGV);
    if (m/^-\?|--help$/) {
        usage();
        exit 0;
    } elsif (m/^--version$/) {
        print_version();
        exit 0;
    } elsif (m/-c(.*)$/) {
        $controlfile = $1;
    } elsif (m/^--$/) {
        last;
    } elsif (m/^-/) {
        usageerr(g_("unknown option '%s'"), $_);
    } else {
        usageerr(g_('no arguments accepted'));
    }
}

my $ctrl = Dpkg::Control::Info->new($controlfile);

print get_build_api($ctrl) . "\n";
