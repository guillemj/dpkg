# -*- mode: cperl;-*-
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

mkdir "t.tmp/a";
mkdir "t.tmp/a/b";
mkdir "t.tmp/a/b/c";
mkdir "t.tmp/a/DEBIAN";
mkdir "t.tmp/debian";
mkdir "t.tmp/debian/a";
mkdir "t.tmp/debian/a/b";
mkdir "t.tmp/debian/a/b/c";
symlink "a/b/c", "t.tmp/cbis";
symlink "/this/does/not/exist", "t.tmp/tmp";
symlink ".", "t.tmp/here";

is(canonpath("t.tmp/./a///b/c"), "t.tmp/a/b/c", "canonpath basic test");
is(canonpath("t.tmp/a/b/../../a/b/c"), "t.tmp/a/b/c", "canonpath and ..");
is(canonpath("t.tmp/a/b/c/../../"), "t.tmp/a", "canonpath .. at end");
is(canonpath("t.tmp/cbis/../"), "t.tmp/cbis/..", "canonpath .. after symlink");

is(resolve_symlink("t.tmp/here/cbis"), "t.tmp/here/a/b/c", "resolve_symlink");
is(resolve_symlink("t.tmp/tmp"), "/this/does/not/exist", "resolve_symlink absolute");
is(resolve_symlink("t.tmp/here"), "t.tmp", "resolve_symlink .");

ok(!check_files_are_the_same("t.tmp/here", "t.tmp"), "Symlink is not the same!");
ok(check_files_are_the_same("t.tmp/here/a", "t.tmp/a"), "Same directory");

is(get_pkg_root_dir("t.tmp/a/b/c"), "t.tmp/a", "get_pkg_root_dir");
is(guess_pkg_root_dir("t.tmp/a/b/c"), "t.tmp/a", "guess_pkg_root_dir");
is(relative_to_pkg_root("t.tmp/a/b/c"), "b/c", "relative_to_pkg_root");

chdir("t.tmp");

ok(!defined(get_pkg_root_dir("debian/a/b/c")), "get_pkg_root_dir undef");
ok(!defined(relative_to_pkg_root("debian/a/b/c")), "relative_to_pkg_root");
is(guess_pkg_root_dir("debian/a/b/c"), "debian/a", "guess_pkg_root_dir fallback");

