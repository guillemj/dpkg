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
use Test::Dpkg qw(:paths);

use File::Spec::Functions qw(rel2abs);

use Dpkg::IPC;
use Dpkg::BuildTree;

plan tests => 5;

my $srcdir = rel2abs($ENV{srcdir} || '.');
my $datadir = "$srcdir/t/dpkg_buildtree";

$ENV{$_} = rel2abs($ENV{$_}) foreach qw(DPKG_DATADIR DPKG_ORIGINS_DIR);

my %is_rootless = (
    'src-build-api-v0' => 1,
    'src-build-api-v1' => 1,
    'src-rrr-binary-targets' => 0,
    'src-rrr-missing' => 1,
    'src-rrr-no' => 1,
);

sub test_is_rootless
{
    my $test = shift;
    my $dirname = "$datadir/$test";

    my $stderr;
    my $res;

    chdir $dirname;
    spawn(
        exec => [
            $ENV{PERL}, "$srcdir/dpkg-buildtree.pl",
            'is-rootless'
        ],
        error_to_string => \$stderr,
        wait_child => 1,
        nocheck => 1,
    );
    $res = $? == 0 ? 1 : 0;
    chdir $datadir;

    return $res;
}

foreach my $test (sort keys %is_rootless) {
    my $exp = $is_rootless{$test};
    my $res = test_is_rootless($test);

    is($res, $exp, "dpkg-buildtree is-rootless on $test not $exp");
}
