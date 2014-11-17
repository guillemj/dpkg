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

use Test::More;
use Test::Dpkg;

eval q{
    use Test::Strict;
    $Test::Strict::TEST_WARNINGS = 1;
};
plan skip_all => 'Test::Strict required for testing syntax' if $@;

if (defined $ENV{srcdir}) {
    chdir $ENV{srcdir} or die "cannot chdir to source directory: $!";
}

my @files = Test::Dpkg::all_perl_files();

plan tests => scalar @files * 3;

for my $file (@files) {
    syntax_ok($file);
    strict_ok($file);
    warnings_ok($file);
}
