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

test_needs_module('Test::Strict');

test_chdir_srcdir();

eval '$Test::Strict::TEST_WARNINGS = 1';
# XXX: Remove once https://github.com/manwar/Test-Strict/pull/37 gets released.
eval 'push @Test::Strict::MODULES_ENABLING_WARNINGS, "v5.36"';

my @files = Test::Dpkg::all_perl_files();

plan tests => scalar @files * 2;

for my $file (@files) {
    strict_ok($file);
    warnings_ok($file);
}
