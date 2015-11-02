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

BEGIN {
    use_ok('Dpkg::Vars');
}

eval { set_source_package('foo%bar') };
ok($@, 'cannot set invalid source package name');
is(get_source_package(), undef, 'invalid source package name unset');

set_source_package('source');
is(get_source_package(), 'source', 'set/get source package name');

set_source_package('source');
is(get_source_package(), 'source', 'reset/get same source package name');

eval { set_source_package('other') };
ok($@, 'cannot set different source package name');

1;
