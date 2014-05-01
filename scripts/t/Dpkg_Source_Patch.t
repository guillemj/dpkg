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

use Test::More tests => 3;

use File::Path qw(make_path);

BEGIN {
    use_ok('Dpkg::Source::Patch');
}

my $srcdir = $ENV{srcdir} || '.';
my $datadir = $srcdir . '/t/Dpkg_Source_Patch';
my $tmpdir = 't.tmp/Dpkg_Source_Patch';

sub test_patch_escape {
    my ($name, $symlink, $patchname, $desc) = @_;

    make_path("$tmpdir/$name-tree");
    make_path("$tmpdir/$name-out");
    symlink "../$name-out", "$tmpdir/$name-tree/$symlink";

    my $patch = Dpkg::Source::Patch->new(filename => "$datadir/$patchname");
    eval {
        $patch->apply("$tmpdir/$name-tree", verbose => 0);
    };
    ok(rmdir "$tmpdir/$name-out", $desc);
}

# This is CVE-2014-0471 with GNU patch >= 2.7
test_patch_escape('c-style-parsed', "\tmp", 'c-style.patch',
                  'Patch cannot escape using known c-style encoded filename');

# This is CVE-2014-0471 with GNU patch < 2.7
test_patch_escape('c-style-unknown', '\\tmp', 'c-style.patch',
                  'Patch cannot escape using unknown c-style encoded filename');

1;
