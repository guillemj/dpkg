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

use Dpkg::IPC;
use File::Spec;
use Test::More;
use File::Compare;
use File::Temp qw(tempfile);

use strict;
use warnings;

plan tests => 3;

my $srcdir = $ENV{srcdir} || '.';
my $datadir = "$srcdir/t/910_merge_changelogs";

my $res;
sub test_merge {
    my ($expected_file, @options) = @_;
    my ($fh, $filename) = tempfile();
    spawn(exec => ["$srcdir/dpkg-mergechangelogs.pl", @options],
	  to_handle => $fh, error_to_file => "/dev/null",
	  wait_child => 1, nocheck => 1);
    my $res = compare($expected_file, $filename);
    if ($res) {
	system("diff -u $expected_file $filename >&2");
    }
    ok($res == 0, "merged changelog matches expected one ($expected_file)");
    unlink($filename);
}

my $has_alg_merge = 1;
eval 'use Algorithm::Merge;';
if ($@) {
    $has_alg_merge = 0;
}

my @input = ("$datadir/ch-old", "$datadir/ch-a", "$datadir/ch-b");
if ($has_alg_merge) {
    test_merge("$datadir/ch-merged", @input);
    test_merge("$datadir/ch-merged-pr", "-m", @input);
} else {
    test_merge("$datadir/ch-merged-basic", @input);
    test_merge("$datadir/ch-merged-pr-basic", "-m", @input);
}
test_merge("$datadir/ch-badver-merged",  ("$datadir/ch-badver-old",
    "$datadir/ch-badver-a", "$datadir/ch-badver-b"));
