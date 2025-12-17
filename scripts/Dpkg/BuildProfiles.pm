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

=encoding utf8

=head1 NAME

Dpkg::BuildProfiles - handle build profiles

=head1 DESCRIPTION

The Dpkg::BuildProfiles module provides functions to handle the build
profiles.

=cut

package Dpkg::BuildProfiles 1.01;

use v5.36;

our @EXPORT_OK = qw(
    get_build_profiles
    set_build_profiles
    build_profile_is_invalid
    parse_build_profiles
    evaluate_restriction_formula
);

use Exporter qw(import);
use List::Util qw(any);

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::BuildEnv;

my $cache_profiles;
my @build_profiles;

=head1 FUNCTIONS

=over 4

=item @profiles = get_build_profiles()

Get an array with the currently active build profiles, taken from
the environment variable B<DEB_BUILD_PROFILES>.

=cut

sub get_build_profiles {
    return @build_profiles if $cache_profiles;

    if (Dpkg::BuildEnv::has('DEB_BUILD_PROFILES')) {
        @build_profiles = split ' ', Dpkg::BuildEnv::get('DEB_BUILD_PROFILES');
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

    $cache_profiles = 1;
    @build_profiles = @profiles;
    Dpkg::BuildEnv::set('DEB_BUILD_PROFILES', join ' ', @profiles);
}

=item $bool = build_profile_is_invalid($string)

Validate a build profile formula.

=cut

my $profile_name_regex = qr{
    !?
    # Be lenient for now. Accept operators for extensibility, uppercase,
    # and package name characters.
    [
        ?/;:=@%*~_
        A-Z
        a-z0-9+.\-
    ]+
}x;

my $restriction_list_regex = qr{
    <
    \s*
    (
        $profile_name_regex
        (?:
            \s+
            $profile_name_regex
        )*
    )
    \s*
    >
}x;

my $restriction_formula_regex = qr{
    ^
    (?:
        \s*
        $restriction_list_regex
    )*
    \s*
    $
}x;


sub build_profile_is_invalid($string)
{
    return $string !~ $restriction_formula_regex;
}

=item @profiles = parse_build_profiles($string)

Parses a build profiles specification, into an array of array references.

It will die on invalid syntax.

=cut

sub parse_build_profiles($string)
{
    if (build_profile_is_invalid($string)) {
        error(g_("'%s' is not a valid build profile restriction formula"),
              $string);
    }

    my @restrictions = $string =~ m{$restriction_list_regex}g;

    return map { [ split ' ' ] } @restrictions;
}

=item evaluate_restriction_formula(\@formula, \@profiles)

Evaluate whether a restriction formula of the form "<foo bar> <baz>", given as
a nested array, is true or false, given the array of enabled build profiles.

=cut

sub evaluate_restriction_formula {
    my ($formula, $profiles) = @_;

    # Restriction formulas are in disjunctive normal form:
    # (foo AND bar) OR (blub AND bla)
    foreach my $restrlist (@{$formula}) {
        my $seen_profile = 1;

        foreach my $restriction (@$restrlist) {
            next if $restriction !~ m/^(!)?(.+)/;

            ## no critic (RegularExpressions::ProhibitCaptureWithoutTest)
            my $negated = defined $1 && $1 eq '!';
            my $profile = $2;
            my $found = any { $_ eq $profile } @{$profiles};

            # If a negative set profile is encountered, stop processing.
            # If a positive unset profile is encountered, stop processing.
            if ($found == $negated) {
                $seen_profile = 0;
                last;
            }
        }

        # This conjunction evaluated to true so we do not have to evaluate
        # the others.
        return 1 if $seen_profile;
    }
    return 0;
}

=back

=head1 CHANGES

=head2 Version 1.01 (dpkg 1.23.0)

New functions: build_profile_is_invalid().

=head2 Version 1.00 (dpkg 1.17.17)

Mark the module as public.

=cut

1;
