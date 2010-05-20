# Copyright © 2008-2009 Raphaël Hertzog <hertzog@debian.org>
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Dpkg::Vendor;

use strict;
use warnings;

our $VERSION = "0.01";

use Dpkg::ErrorHandling;
use Dpkg::Gettext;
use Dpkg::Control::Hash;

use base qw(Exporter);
our @EXPORT_OK = qw(get_vendor_info get_current_vendor get_vendor_file
                    get_vendor_object run_vendor_hook);

my $origins = "/etc/dpkg/origins";
$origins = $ENV{DPKG_ORIGINS_DIR} if $ENV{DPKG_ORIGINS_DIR};

=encoding utf8

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

Returns a Dpkg::Control object with the information parsed from the
corresponding vendor file in /etc/dpkg/origins/. If $name is omitted,
it will use /etc/dpkg/origins/default which is supposed to be a symlink
to the vendor of the currently installed operating system. Returns undef
if there's no file for the given vendor.

=cut

sub get_vendor_info(;$) {
    my $vendor = shift || "default";
    my $file = get_vendor_file($vendor);
    return undef unless $file;
    my $fields = Dpkg::Control::Hash->new();
    $fields->load($file) || error(_g("%s is empty"), $file);
    return $fields;
}

=item $name = Dpkg::Vendor::get_vendor_file($name)

Check if there's a file for the given vendor and returns its
name.

=cut

sub get_vendor_file(;$) {
    my $vendor = shift || "default";
    my $file;
    my @tries = ($vendor, lc($vendor), ucfirst($vendor), ucfirst(lc($vendor)));
    if ($vendor =~ s/\s+/-/) {
        push @tries, $vendor, lc($vendor), ucfirst($vendor), ucfirst(lc($vendor));
    }
    foreach my $name (@tries) {
        $file = "$origins/$name" if -e "$origins/$name";
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

=item $object = Dpkg::Vendor::get_vendor_object($name)

Return the Dpkg::Vendor::* object of the corresponding vendor.
If $name is omitted, return the object of the current vendor.
If no vendor can be identified, then return the Dpkg::Vendor::Default
object.

=cut

my %OBJECT_CACHE;
sub get_vendor_object {
    my $vendor = shift || get_current_vendor() || "Default";
    return $OBJECT_CACHE{$vendor} if exists $OBJECT_CACHE{$vendor};

    my ($obj, @names);
    if ($vendor ne "Default") {
        push @names, $vendor, lc($vendor), ucfirst($vendor), ucfirst(lc($vendor));
    }
    foreach my $name (@names, "Default") {
        eval qq{
            require Dpkg::Vendor::$name;
            \$obj = Dpkg::Vendor::$name->new();
        };
        last unless $@;
    }
    $OBJECT_CACHE{$vendor} = $obj;
    return $obj;
}

=item Dpkg::Vendor::run_vendor_hook($hookid, @params)

Run a hook implemented by the current vendor object.

=cut

sub run_vendor_hook {
    my $vendor_obj = get_vendor_object();
    $vendor_obj->run_hook(@_);
}

=back

=cut

1;
