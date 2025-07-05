# Copyright © 2014-2025 Guillem Jover <guillem@debian.org>
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

Dpkg::SysInfo - system information support

=head1 DESCRIPTION

This module implements system information functions used to gather data
about the current system.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dpkg::SysInfo 0.01;

use v5.36;

our @EXPORT_OK = qw(
    get_num_processors
);

use Exporter qw(import);

sub get_num_processors()
{
    my $nproc;

    # Most Unices.
    $nproc = qx(getconf _NPROCESSORS_ONLN 2>/dev/null);

    # Fallback for at least Irix.
    $nproc = qx(getconf _NPROC_ONLN 2>/dev/null) if $?;

    # Fallback to serial execution if cannot infer the number of online
    # processors.
    $nproc = '1' if $?;

    chomp $nproc;

    return $nproc;
}

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
