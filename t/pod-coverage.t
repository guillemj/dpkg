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

use Test::More;
use Test::Dpkg qw(:needs :paths);

test_needs_author();
test_needs_module('Test::Pod::Coverage');

test_chdir_srcdir();

my @modules_todo = qw(Dpkg::Arch Dpkg::Source::Package);
my @modules = all_pod_modules(@modules_todo);

plan tests => scalar @modules + scalar @modules_todo;

for my $module (@modules) {
    pod_coverage_ok($module);
}

TODO: {
    local $TODO = 'modules partially documented';

    for my $module (@modules_todo) {
        pod_coverage_ok($module);
    }
}
