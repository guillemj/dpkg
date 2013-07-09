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

use strict;
use warnings;

use Test::More tests => 7;

BEGIN {
    use_ok('Dpkg::Util', qw(:list));
}

my @array = qw(foo bar quux baz);
my %hash = (foo => 1, bar => 10, quux => 100, baz => 200);

ok(any { 'bar' eq $_ } @array, 'array has item');

ok(!any { 'notfound' eq $_ } @array, 'array does not have item');
ok(none { 'notfound' eq $_ } @array, 'array lacks item');

ok(any { m/^quu/ } @array, 'array has item matching regexp');
ok(none { m/^notfound/ } @array, 'array lacks item matching regexp');

ok(any { m/^quu/ } keys %hash, 'hash has item matching regexp');

1;
