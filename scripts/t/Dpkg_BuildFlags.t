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

use Test::More tests => 15;

BEGIN {
    use_ok('Dpkg::BuildFlags');
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

$bf->append('DPKGFLAGS', '-Wl,other', 'vendor', 0);
is($bf->get('DPKGFLAGS'), '-Wflag -fsome -Wl,other', 'get appended flag');
is($bf->get_origin('DPKGFLAGS'), 'vendor', 'flag has a vendor origin');
ok(!$bf->is_maintainer_modified('DPKGFLAGS'), 'append marked flag as non-maint modified');

$bf->prepend('DPKGFLAGS', '-Idir', 'env', 1);
is($bf->get('DPKGFLAGS'), '-Idir -Wflag -fsome -Wl,other', 'get prepended flag');
is($bf->get_origin('DPKGFLAGS'), 'env', 'flag has an env origin');
ok($bf->is_maintainer_modified('DPKGFLAGS'), 'prepend marked flag as maint modified');

# TODO: Add more test cases.

1;
