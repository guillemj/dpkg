# Copyright 2007 Raphaël Hertzog <hertzog@debian.org>

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

package Dpkg::Path;

use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(get_pkg_root_dir relative_to_pkg_root);

=head1 NAME

Dpkg::Path - some common path handling functions

=head1 DESCRIPTION

It provides some functions to handle various path.

=head1 METHODS

=over 8

=item get_pkg_root_dir($file)

This function will scan upwards the hierarchy of directory to find out
the directory which contains the "DEBIAN" sub-directory and it will return
its path. This directory is the root directory of a package being built.

If no DEBIAN subdirectory is found, it will return undef.

=cut

sub get_pkg_root_dir($) {
    my $file = shift;
    $file =~ s{/+$}{};
    $file =~ s{/+[^/]+$}{} if not -d $file;
    while ($file) {
	return $file if -d "$file/DEBIAN";
	last if $file !~ m{/};
	$file =~ s{/+[^/]+$}{};
    }
    return undef;
}

=item relative_to_pkg_root($file)

Returns the filename relative to get_pkg_root_dir($file).

=cut

sub relative_to_pkg_root($) {
    my $file = shift;
    my $pkg_root = get_pkg_root_dir($file);
    if (defined $pkg_root) {
	$pkg_root .= "/";
	return $file if ($file =~ s/^\Q$pkg_root\E//);
    }
    return undef;
}

=back

=head1 AUTHOR

Raphael Hertzog <hertzog@debian.org>.

=cut

1;
