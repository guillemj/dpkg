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

use Test::More tests => 6;

use_ok('Dpkg::Package');

ok(pkg_name_is_illegal(undef), 'package name is undef');
ok(pkg_name_is_illegal(''), 'package name is empty');
ok(pkg_name_is_illegal('%_&'), 'package name has invalid chars');
ok(pkg_name_is_illegal('ABC'), 'package name has uppercase chars');
ok(pkg_name_is_illegal('-abc'), 'package name has a dash');

1;
