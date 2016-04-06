# Copyright © 2007 Frank Lichtenheld <djpig@debian.org>
# Copyright © 2010, 2013-2016 Guillem Jover <guillem@debian.org>
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

package Dpkg::Build::Types;

use strict;
use warnings;

our $VERSION = '0.01';
our @EXPORT = qw(
    BUILD_DEFAULT
    BUILD_SOURCE
    BUILD_ARCH_DEP
    BUILD_ARCH_INDEP
    BUILD_BINARY
    BUILD_FULL
    build_has_any
    build_has_all
    build_has_none
    build_is
    set_build_type
);

use Exporter qw(import);

use Dpkg::Gettext;
use Dpkg::ErrorHandling;

=encoding utf8

=head1 NAME

Dpkg::Build::Types - track build types

=head1 DESCRIPTION

The Dpkg::Build::Types module is used by various tools to track and decide
what artifacts need to be built.

The build types are bit constants that are exported by default. Multiple
types can be ORed.

=head1 CONSTANTS

=over 4

=item BUILD_DEFAULT

This build is the default.

=item BUILD_SOURCE

This build includes source artifacts.

=item BUILD_ARCH_DEP

This build includes architecture dependent binary artifacts.

=item BUILD_ARCH_INDEP

This build includes architecture independent binary artifacts.

=item BUILD_BINARY

This build includes binary artifacts.

=item BUILD_FULL

This build includes source and binary artifacts.

=cut

# Simple types.
use constant {
    BUILD_DEFAULT      => 1,
    BUILD_SOURCE       => 2,
    BUILD_ARCH_DEP     => 4,
    BUILD_ARCH_INDEP   => 8,
};

# Composed types.
use constant BUILD_BINARY => BUILD_ARCH_DEP | BUILD_ARCH_INDEP;
use constant BUILD_FULL   => BUILD_BINARY | BUILD_SOURCE;

my $current_type = BUILD_FULL | BUILD_DEFAULT;
my $current_option = undef;

=back

=head1 FUNCTIONS

=over 4

=item build_has_any($bits)

Return a boolean indicating whether the current build type has any of the
specified $bits.

=cut

sub build_has_any
{
    my ($bits) = @_;

    return $current_type & $bits;
}

=item build_has_all($bits)

Return a boolean indicating whether the current build type has all the
specified $bits.

=cut

sub build_has_all
{
    my ($bits) = @_;

    return ($current_type & $bits) == $bits;
}

=item build_has_none($bits)

Return a boolean indicating whether the current build type has none of the
specified $bits.

=cut

sub build_has_none
{
    my ($bits) = @_;

    return !($current_type & $bits);
}

=item build_is($bits)

Return a boolean indicating whether the current build type is the specified
set of $bits.

=cut

sub build_is
{
    my ($bits) = @_;

    return $current_type == $bits;
}

=item set_build_type($build_type, $build_option)

Set the current build type to $build_type, which was specified via the
$build_option command-line option.

=cut

sub set_build_type
{
    my ($build_type, $build_option) = @_;

    usageerr(g_('cannot combine %s and %s'), $current_option, $build_option)
        if build_has_none(BUILD_DEFAULT) and $current_type != $build_type;

    $current_type = $build_type;
    $current_option = $build_option;
}

=back

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
