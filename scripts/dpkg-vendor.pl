#!/usr/bin/perl
#
# dpkg-vendor
#
# Copyright © 2009 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2009,2012 Guillem Jover <guillem@debian.org>
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
use Dpkg::Vendor qw(get_vendor_dir get_vendor_info get_current_vendor);

textdomain('dpkg-dev');

sub usage {
    printf g_(
"Usage: %s [<option>...] [<command>]\n" .
    ''), $Dpkg::PROGNAME;
    print_option_sep();

    printf g_(
"Commands:\n" .
    '');
    print_option(g_(
"      --is <vendor>\n" .
"          Returns true if current vendor is <vendor>.\n" .
    ''));
    print_option(g_(
"      --derives-from <vendor>\n" .
"          Returns true if current vendor derives from <vendor>.\n" .
    ''));
    print_option(g_(
"      --query <field>\n" .
"          Print the content of the vendor-specific field.\n" .
    ''));
    print_option(g_(
"      --help\n" .
"          Show this help message.\n" .
    ''));
    print_option(g_(
"      --version\n" .
"          Show the version.\n" .
    ''));
    print_option_sep();

    printf g_(
"Options:\n" .
    '');
    print_option(g_(
"      --vendor <vendor>\n" .
"          Assume <vendor> is the current vendor.\n" .
    ''));
}

my ($vendor, $param, $action);

while (@ARGV) {
    $_ = shift(@ARGV);
    if (m/^--vendor$/) {
        $vendor = shift(@ARGV);
        usageerr(g_('%s needs a parameter'), $_) unless defined $vendor;
    } elsif (m/^--(is|derives-from|query)$/) {
        usageerr(g_('two commands specified: --%s and --%s'), $1, $action)
            if defined($action);
        $action = $1;
        $param = shift(@ARGV);
        usageerr(g_('%s needs a parameter'), $_) unless defined $param;
    } elsif (m/^-(?:\?|-help)$/) {
        usage();
        exit 0;
    } elsif (m/^--version$/) {
        print_version();
        exit 0;
    } else {
        usageerr(g_("unknown option '%s'"), $_);
    }
}

usageerr(g_('need an action option')) unless defined($action);

# Uses $ENV{DEB_VENDOR} if set.
$vendor //= get_current_vendor();

my $info = get_vendor_info($vendor);
unless (defined($info)) {
    error(g_('vendor %s does not exist in %s'), $vendor || 'default',
          get_vendor_dir());
}

if ($action eq 'is') {
    exit(0) if lc($param) eq lc($info->{'Vendor'});
    exit(1);
} elsif ($action eq 'derives-from') {
    exit(0) if lc($param) eq lc($info->{'Vendor'});
    while (defined($info) && exists $info->{'Parent'}) {
        $info = get_vendor_info($info->{'Parent'});
        exit(0) if lc($param) eq lc($info->{'Vendor'});
    }
    exit(1);
} elsif ($action eq 'query') {
    if (exists $info->{$param}) {
        print $info->{$param} . "\n";
        exit(0);
    } else {
        exit(1);
    }
}
