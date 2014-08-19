# Copyright © 2013 Guillem Jover <guillem@debian.org>
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

package Dpkg::BuildProfiles;

use strict;
use warnings;

our $VERSION = '0.01';
our @EXPORT_OK = qw(get_build_profiles set_build_profiles parse_build_profiles
                    evaluate_restriction_formula);

use Exporter qw(import);

use Dpkg::BuildEnv;

my $cache_profiles;
my @build_profiles;

=encoding utf8

=head1 NAME

Dpkg::BuildProfiles - handle build profiles

=head1 DESCRIPTION

The Dpkg::BuildProfiles module provides functions to handle the build
profiles.

=head1 FUNCTIONS

=over 4

=item my @profiles = get_build_profiles()

Get an array with the currently active build profiles, taken from
the environment variable B<DEB_BUILD_PROFILES>.

=cut

sub get_build_profiles {
    return @build_profiles if $cache_profiles;

    if (Dpkg::BuildEnv::has('DEB_BUILD_PROFILES')) {
        @build_profiles = split / /, Dpkg::BuildEnv::get('DEB_BUILD_PROFILES');
    }
    $cache_profiles = 1;

    return @build_profiles;
}

=item set_build_profiles(@profiles)

Set C<@profiles> as the current active build profiles, by setting
the environment variable B<DEB_BUILD_PROFILES>.

=cut

sub set_build_profiles {
    my (@profiles) = @_;

    @build_profiles = @profiles;
    Dpkg::BuildEnv::set('DEB_BUILD_PROFILES', join ' ', @profiles);
}

=item my @profiles = parse_build_profiles($string)

Parses a build profiles specification, into an array.

=cut

sub parse_build_profiles {
    my $string = shift;

    return map { lc } split /\s+/, $string;
}

=item evaluate_restriction_formula(\@formula, \@profiles)

Evaluate whether a restriction list, is true or false, given the array of
enabled build profiles.

=cut

sub evaluate_restriction_formula {
    my ($restrictions, $build_profiles) = @_;

    my $seen_profile = 0;
    foreach my $restriction (@{$restrictions}) {
        # Determine if this restriction is negated, and within the "profile"
        # namespace, otherwise it does not concern this check.
        next if $restriction !~ m/^(!)?profile\.(.*)/;

        my $negated = defined $1 && $1 eq '!';
        my $profile = $2;

        # Determine if the restriction matches any of the specified profiles.
        my $found = any { $_ eq $profile } @{$build_profiles};

        if ($negated) {
            if ($found) {
                $seen_profile = 0;
                last;
            } else {
                # "!profile.this" includes by default all other profiles
                # unless they also appear in a "!profile.other".
                $seen_profile = 1;
            }
        } elsif ($found) {
            $seen_profile = 1;
            last;
        }
    }
    return $seen_profile;
}

=back

=cut

1;
