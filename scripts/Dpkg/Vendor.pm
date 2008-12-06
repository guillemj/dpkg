# Copyright © 2008 Raphaël Hertzog <hertzog@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Dpkg::Vendor;

use strict;
use warnings;

use Dpkg::ErrorHandling;
use Dpkg::Gettext;
use Dpkg::Cdata;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(get_vendor_info get_current_vendor get_vendor_file);

=head1 NAME

Dpkg::Vendor - get access to some vendor specific information

=head1 DESCRIPTION

The files in /etc/dpkg/origins/ can provide information about various
vendors who are providing Debian packages. Currently those files look like
this:

  Vendor: Debian
  Vendor-URL: http://www.debian.org/
  Bugs: debbugs://bugs.debian.org

The file should be named according to the vendor name.

=head1 FUNCTIONS

=over 4

=item $fields = Dpkg::Vendor::get_vendor_info($name)

Returns a Dpkg::Fields object with the information parsed from the
corresponding vendor file in /etc/dpkg/origins/. If $name is omitted,
it will use /etc/dpkg/origins/default which is supposed to be a symlink
to the vendor of the currently installed operating system. Returns undef
if there's no file for the given vendor.

=cut
sub get_vendor_info(;$) {
    my $vendor = shift || "default";
    my $file = get_vendor_file($vendor);
    return undef unless $file;
    open(my $fh, "<", $file) || syserr(_g("cannot read %s"), $file);
    my $fields = parsecdata($fh, $file);
    close($fh);
    return $fields;
}

=item $name = Dpkg::Vendor::get_vendor_file($name)

Check if there's a file for the given vendor and returns its
name.

=cut
sub get_vendor_file(;$) {
    my $vendor = shift || "default";
    my $file;
    foreach my $name ($vendor, lc($vendor), ucfirst($vendor)) {
        $file = "/etc/dpkg/origins/$name" if -e "/etc/dpkg/origins/$name";
    }
    return $file;
}

=item $name = Dpkg::Vendor::get_current_vendor()

Returns the name of the current vendor. If DEB_VENDOR is set, it uses
that first, otherwise it falls back to parsing /etc/dpkg/origins/default.
If that file doesn't exist, it returns undef.

=cut
sub get_current_vendor() {
    my $f;
    if ($ENV{'DEB_VENDOR'}) {
        $f = get_vendor_info($ENV{'DEB_VENDOR'});
        return $f->{'Vendor'} if defined $f;
    }
    $f = get_vendor_info();
    return $f->{'Vendor'} if defined $f;
    return undef;
}

1;
