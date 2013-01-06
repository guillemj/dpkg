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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use Test::More tests => 6;

use strict;
use warnings;

use_ok('Dpkg::Package');

ok(pkg_name_is_illegal(undef));
ok(pkg_name_is_illegal(""));
ok(pkg_name_is_illegal("%_&"));
ok(pkg_name_is_illegal("ABC"));
ok(pkg_name_is_illegal("-abc"));

1;
