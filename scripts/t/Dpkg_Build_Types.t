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

use Test::More tests => 12;

BEGIN {
    use_ok('Dpkg::Build::Types');
}

ok(build_is(BUILD_DEFAULT | BUILD_FULL), 'build is default full');

set_build_type(BUILD_DEFAULT | BUILD_BINARY, '--default-binary');

ok(build_is(BUILD_DEFAULT | BUILD_BINARY), 'build is default binary');

set_build_type(BUILD_SOURCE_INDEP, '--source-indep');

ok(build_is(BUILD_SOURCE_INDEP), 'build is source indep');
ok(!build_is(BUILD_SOURCE_DEP), 'build is not source dep');
ok(build_has(BUILD_SOURCE), 'build source indep has source');
ok(build_has(BUILD_ARCH_INDEP), 'build source indep has arch indep');
ok(build_has_not(BUILD_DEFAULT), 'build source indep has not default');
ok(build_has_not(BUILD_ARCH_DEP), 'build source indep has not arch dep');
ok(build_has_not(BUILD_BINARY), 'build source indep has not binary');
ok(build_has_not(BUILD_SOURCE_DEP), 'build source indep has not source dep');
ok(build_has_not(BUILD_FULL), 'build source indep has not full');

1;
