#!/usr/bin/perl
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

use Test::More tests => 24;

use ok 'Dpkg::BuildProfiles', qw(
    build_profile_is_invalid
    parse_build_profiles
    set_build_profiles
    get_build_profiles
);

# TODO: Add actual test cases.

my $formula;

ok(!build_profile_is_invalid(''),
    'check that build profiles with no characters are valid');
ok(!build_profile_is_invalid('<nocheck>'),
    'check that build profiles with a valid single element are valid');
ok(!build_profile_is_invalid('<nocheck nodoc> <pkg/dpkg/author-checks>'),
    'check that build profiles with a valid formula are valid');

ok(build_profile_is_invalid('<invalid> + <characters>'),
    'check that build profiles with invalid characters are invalid');
TODO: {
    local $TODO = 'workaround due to incorrect API uses';
ok(build_profile_is_invalid('missing angle brackets'),
    'check that build profiles with missing opening/closing angle brackets are invalid');
}
ok(build_profile_is_invalid('<missing angle brackets <here too'),
    'check that build profiles with missing closing angle brackets are invalid 1');
ok(build_profile_is_invalid('<missing angle brackets <here too>'),
    'check that build profiles with missing closing angle brackets are invalid 2');
ok(build_profile_is_invalid('missing angle> brackets>'),
    'check that build profiles with missing opening angle brackets are invalid 1');
ok(build_profile_is_invalid('missing angle> <brackets>'),
    'check that build profiles with missing opening angle brackets are invalid 2');

$formula = [ ];
is_deeply([ parse_build_profiles('') ], $formula,
    'parse build profiles formula empty');

$formula = [ [ qw(nocheck) ] ];
is_deeply([ parse_build_profiles('<nocheck>') ], $formula,
    'parse build profiles formula single');

$formula = [ [ qw(nocheck nodoc stage1) ] ];
is_deeply([ parse_build_profiles('<nocheck nodoc stage1>') ], $formula,
    'parse build profiles formula AND');

$formula = [ [ qw(nocheck) ], [ qw(nodoc) ] ];
is_deeply([ parse_build_profiles('<nocheck> <nodoc>') ], $formula,
    'parse build profiles formula OR');

$formula = [ [ qw(nocheck nodoc) ], [ qw(stage1) ] ];
is_deeply([ parse_build_profiles('<nocheck nodoc> <stage1>') ], $formula,
    'parse build profiles formula AND, OR');

$formula = [ [ qw(nocheck !nodoc) ], [ qw(!stage1) ] ];
is_deeply([ parse_build_profiles('<nocheck !nodoc> <!stage1>') ], $formula,
    'parse build profiles formula negations');

{
    local $ENV{DEB_BUILD_PROFILES} = 'cross nodoc profile.name';
    is_deeply([ get_build_profiles() ], [ qw(cross nodoc profile.name) ],
        'get active build profiles from environment');
}

eval { parse_build_profiles('<invalid> + <characters>') };
ok($@, 'fail to parse build profiles with invalid characters');

TODO: {
    local $TODO = 'workaround due to incorrect API uses';
eval { parse_build_profiles('missing angle brackets') };
ok($@, 'fail to parse build profiles with missing opening/closing angles brackets');
}

eval { parse_build_profiles('<missing angle brackets <here too') };
ok($@, 'fail to parse build profiles with missing closing angles brackets 1');

eval { parse_build_profiles('<missing angle brackets <here too>') };
ok($@, 'fail to parse build profiles with missing closing angles brackets 2');

eval { parse_build_profiles('missing angle> brackets>') };
ok($@, 'fail to parse build profiles with missing opening angles brackets 1');

eval { parse_build_profiles('missing angle> <brackets>') };
ok($@, 'fail to parse build profiles with missing opening angles brackets 2');

set_build_profiles(qw(nocheck stage1));
is_deeply([ get_build_profiles() ], [ qw(nocheck stage1) ],
    'get active build profiles explicitly set');
