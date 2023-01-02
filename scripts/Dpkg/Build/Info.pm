# Copyright © 2016-2022 Guillem Jover <guillem@debian.org>
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

package Dpkg::Build::Info;

use strict;
use warnings;

our $VERSION = '1.02';
our @EXPORT_OK = qw(
    get_build_env_whitelist
    get_build_env_allowed
);

use Exporter qw(import);

use Dpkg::BuildInfo;

=encoding utf8

=head1 NAME

Dpkg::Build::Info - handle build information

=head1 DESCRIPTION

The Dpkg::Build::Info module provides functions to handle the build
information.

This module is deprecated, use Dpkg::BuildInfo instead.

=head1 FUNCTIONS

=over 4

=item @envvars = get_build_env_allowed()

Get an array with the allowed list of environment variables that can affect
the build, but are still not privacy revealing.

This is a deprecated alias for Dpkg::BuildInfo::get_build_env_allowed().

=cut

sub get_build_env_allowed {
    #warnings::warnif('deprecated',
    #    'Dpkg::Build::Info::get_build_env_allowed() is deprecated, ' .
    #    'use Dpkg::BuildInfo::get_build_env_allowed() instead');
    return Dpkg::BuildInfo::get_build_env_allowed();
}

=item @envvars = get_build_env_whitelist()

This is a deprecated alias for Dpkg::BuildInfo::get_build_env_allowed().

=cut

sub get_build_env_whitelist {
    warnings::warnif('deprecated',
        'Dpkg::Build::Info::get_build_env_whitelist() is deprecated, ' .
        'use Dpkg::BuildInfo::get_build_env_allowed() instead');
    return Dpkg::BuildInfo::get_build_env_allowed();
}

=back

=head1 CHANGES

=head2 Version 1.02 (dpkg 1.21.14)

Deprecate module: replaced by Dpkg::BuildInfo.

=head2 Version 1.01 (dpkg 1.20.1)

New function: get_build_env_allowed().

Deprecated function: get_build_env_whitelist().

=head2 Version 1.00 (dpkg 1.18.14)

Mark the module as public.

=cut

1;
