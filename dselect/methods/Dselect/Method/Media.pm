# Copyright © 2025 Guillem Jover <guillem@debian.org>
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

=encoding utf8

=head1 NAME

Dselect::Method::Media - dselect Media method support

=head1 DESCRIPTION

This module provides support functions for the Media method.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dselect::Method::Media 0.01;

use v5.36;

use Dpkg::File;

our @EXPORT = qw(
    get_disk_label
);

use Exporter qw(import);

sub get_disk_label($mount_point, $hier_base)
{
    my $info_file;
    if (-r "$mount_point/.disk/info") {
        $info_file = "$mount_point/.disk/info";
    } elsif (-r "$mount_point/$hier_base/.disk/info") {
        $info_file = "$mount_point/$hier_base/.disk/info";
    } else {
        return 'Unknown disc';
    }

    my $disk_label = file_slurp($info_file);
    chomp $disk_label;

    return $disk_label;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
