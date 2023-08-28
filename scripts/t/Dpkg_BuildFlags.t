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

use strict;
use warnings;

use Test::More tests => 40;

BEGIN {
    $ENV{DEB_BUILD_ARCH} = 'amd64';
    $ENV{DEB_HOST_ARCH} = 'amd64';
    use_ok('Dpkg::BuildFlags');
}

sub test_has_flag
{
    my ($bf, $flag, $optflag) = @_;

    my $value = $bf->get($flag);
    ok($value =~ m/$optflag/, "$flag contains $optflag: $value");
}

sub test_has_noflag
{
    my ($bf, $flag, $optflag) = @_;

    my $value = $bf->get($flag);
    ok($value !~ m/$optflag/, "$flag does not contain $optflag: $value");
}
my $bf = Dpkg::BuildFlags->new();

ok($bf->has('CPPFLAGS'), 'CPPFLAGS is present');
is($bf->get_origin('CPPFLAGS'), 'vendor', 'CPPFLAGS has a vendor origin');

$bf->set('DPKGFLAGS', '-Wflag -On -fsome', 'system');
is($bf->get('DPKGFLAGS'), '-Wflag -On -fsome', 'get flag');
is($bf->get_origin('DPKGFLAGS'), 'system', 'flag has a system origin');
ok(!$bf->is_maintainer_modified('DPKGFLAGS'), 'set marked flag as non-maint modified');

$bf->strip('DPKGFLAGS', '-On', 'user', undef);
is($bf->get('DPKGFLAGS'), '-Wflag -fsome', 'get stripped flag');
is($bf->get_origin('DPKGFLAGS'), 'user', 'flag has a user origin');
ok(!$bf->is_maintainer_modified('DPKGFLAGS'), 'strip marked flag as non-maint modified');

my @strip_tests = (
    {
        value => '-fsingle',
        strip => '-fsingle',
        exp => '',
    }, {
        value => '-fdupe -fdupe',
        strip => '-fdupe',
        exp => '',
    }, {
        value => '-Wa -fdupe -fdupe -Wb',
        strip => '-fdupe',
        exp => '-Wa -Wb',
    }, {
        value => '-fdupe -Wa -Wb -fdupe',
        strip => '-fdupe',
        exp => '-Wa -Wb',
    }, {
        value => '-fdupe -Wa -fdupe -Wb',
        strip => '-fdupe',
        exp => '-Wa -Wb',
    }, {
        value => '-Wa -fdupe -Wb -fdupe',
        strip => '-fdupe',
        exp => '-Wa -Wb',
    }
);

foreach my $test (@strip_tests) {
    $bf->set('DPKGSTRIPFLAGS', $test->{value}, 'system');
    $bf->strip('DPKGSTRIPFLAGS', $test->{strip}, 'user', undef);
    is($bf->get('DPKGSTRIPFLAGS'), $test->{exp},
        "strip flag '$test->{strip}' from '$test->{value}' to '$test->{exp}'");
}

$bf->append('DPKGFLAGS', '-Wl,other', 'vendor', 0);
is($bf->get('DPKGFLAGS'), '-Wflag -fsome -Wl,other', 'get appended flag');
is($bf->get_origin('DPKGFLAGS'), 'vendor', 'flag has a vendor origin');
ok(!$bf->is_maintainer_modified('DPKGFLAGS'), 'append marked flag as non-maint modified');

$bf->prepend('DPKGFLAGS', '-Idir', 'env', 1);
is($bf->get('DPKGFLAGS'), '-Idir -Wflag -fsome -Wl,other', 'get prepended flag');
is($bf->get_origin('DPKGFLAGS'), 'env', 'flag has an env origin');
ok($bf->is_maintainer_modified('DPKGFLAGS'), 'prepend marked flag as maint modified');

my %known_features = (
    future => [ qw(
        lfs
    ) ],
    abi => [ qw(
        lfs
        time64
    ) ],
    hardening => [ qw(
        bindnow
        branch
        format
        fortify
        pie
        relro
        stackclash
        stackprotector
        stackprotectorstrong
    ) ],
    qa => [ qw(
        bug
        canary
    ) ],
    reproducible => [ qw(
        fixdebugpath
        fixfilepath
        timeless
    ) ],
    optimize => [ qw(
        lto
    ) ],
    sanitize => [ qw(
        address
        leak
        thread
        undefined
    ) ],
);

is_deeply([ sort $bf->get_feature_areas() ], [ sort keys %known_features ],
          'supported feature areas');

foreach my $area (sort keys %known_features) {
    ok($bf->has_features($area), "has feature area $area");
    my %features = $bf->get_features($area);
    is_deeply([ sort keys %features ],
              $known_features{$area},
              "supported features for area $area");
}

# Test lfs alias from abi to future, we need a 32-bit arch that does does
# not currently have this flag built-in.
$ENV{DEB_BUILD_ARCH} = 'i386';
$ENV{DEB_HOST_ARCH} = 'i386';

$ENV{DEB_BUILD_MAINT_OPTIONS} = 'future=+lfs';
$bf = Dpkg::BuildFlags->new();
test_has_flag($bf, 'CPPFLAGS', '-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64');

$ENV{DEB_BUILD_MAINT_OPTIONS} = 'abi=+lfs';
$bf = Dpkg::BuildFlags->new();
test_has_flag($bf, 'CPPFLAGS', '-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64');

$ENV{DEB_BUILD_MAINT_OPTIONS} = 'future=-lfs abi=+lfs';
$bf = Dpkg::BuildFlags->new();
test_has_flag($bf, 'CPPFLAGS', '-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64');

$ENV{DEB_BUILD_MAINT_OPTIONS} = 'future=+lfs abi=-lfs';
$bf = Dpkg::BuildFlags->new();
test_has_noflag($bf, 'CPPFLAGS', '-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64');

# TODO: Add more test cases.
