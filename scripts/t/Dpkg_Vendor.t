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

use Test::More tests => 5;

use_ok('Dpkg::Vendor', qw(get_current_vendor get_vendor_object));

my ($vendor, $obj);

$vendor = get_current_vendor();
is($vendor, 'Debian', 'Check current vendor name');

$obj = get_vendor_object();
is(ref($obj), 'Dpkg::Vendor::Debian', 'Check current vendor object');
$obj = get_vendor_object('gNewSense');
is(ref($obj), 'Dpkg::Vendor::Debian', 'Check parent fallback vendor object');
$obj = get_vendor_object('Ubuntu');
is(ref($obj), 'Dpkg::Vendor::Ubuntu', 'Check specific vendor object');
