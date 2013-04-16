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

use Test::More tests => 16;

use strict;
use warnings;

use_ok('Dpkg::Path', 'canonpath', 'resolve_symlink',
       'check_files_are_the_same', 'get_pkg_root_dir',
       'guess_pkg_root_dir', 'relative_to_pkg_root');

my $tmpdir = 't.tmp/500_Dpkg_Path';

mkdir $tmpdir;
mkdir "$tmpdir/a";
mkdir "$tmpdir/a/b";
mkdir "$tmpdir/a/b/c";
mkdir "$tmpdir/a/DEBIAN";
mkdir "$tmpdir/debian";
mkdir "$tmpdir/debian/a";
mkdir "$tmpdir/debian/a/b";
mkdir "$tmpdir/debian/a/b/c";
symlink "a/b/c", "$tmpdir/cbis";
symlink "/this/does/not/exist", "$tmpdir/tmp";
symlink ".", "$tmpdir/here";

is(canonpath("$tmpdir/./a///b/c"), "$tmpdir/a/b/c", "canonpath basic test");
is(canonpath("$tmpdir/a/b/../../a/b/c"), "$tmpdir/a/b/c", "canonpath and ..");
is(canonpath("$tmpdir/a/b/c/../../"), "$tmpdir/a", "canonpath .. at end");
is(canonpath("$tmpdir/cbis/../"), "$tmpdir/cbis/..", "canonpath .. after symlink");

is(resolve_symlink("$tmpdir/here/cbis"), "$tmpdir/here/a/b/c", "resolve_symlink");
is(resolve_symlink("$tmpdir/tmp"), "/this/does/not/exist", "resolve_symlink absolute");
is(resolve_symlink("$tmpdir/here"), $tmpdir, "resolve_symlink .");

ok(!check_files_are_the_same("$tmpdir/here", $tmpdir), "Symlink is not the same!");
ok(check_files_are_the_same("$tmpdir/here/a", "$tmpdir/a"), "Same directory");

is(get_pkg_root_dir("$tmpdir/a/b/c"), "$tmpdir/a", "get_pkg_root_dir");
is(guess_pkg_root_dir("$tmpdir/a/b/c"), "$tmpdir/a", "guess_pkg_root_dir");
is(relative_to_pkg_root("$tmpdir/a/b/c"), "b/c", "relative_to_pkg_root");

chdir($tmpdir);

ok(!defined(get_pkg_root_dir("debian/a/b/c")), "get_pkg_root_dir undef");
ok(!defined(relative_to_pkg_root("debian/a/b/c")), "relative_to_pkg_root");
is(guess_pkg_root_dir("debian/a/b/c"), "debian/a", "guess_pkg_root_dir fallback");
