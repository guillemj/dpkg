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

use Test::More tests => 33;
use Test::Dpkg qw(:paths);

use Cwd qw(realpath);
use File::Path qw(make_path);;
use File::Spec::Functions qw(abs2rel);

use_ok('Dpkg::Path', 'canonpath', 'resolve_symlink',
       'check_files_are_the_same',
       'check_directory_traversal',
       'get_pkg_root_dir',
       'guess_pkg_root_dir', 'relative_to_pkg_root');

my $tmpdir = test_get_temp_path();

sub gen_file
{
    my ($pathname) = @_;

    open my $fh, '>', $pathname or BAIL_OUT("cannot create file $pathname");
    close $fh;
}

make_path("$tmpdir/a/b/c");
make_path("$tmpdir/a/DEBIAN");
make_path("$tmpdir/debian/a/b/c");
symlink 'a/b/c', "$tmpdir/cbis";
symlink '/this/does/not/exist', "$tmpdir/tmp";
symlink '.', "$tmpdir/here";

is(canonpath("$tmpdir/./a///b/c"), "$tmpdir/a/b/c", 'canonpath basic test');
is(canonpath("$tmpdir/a/b/../../a/b/c"), "$tmpdir/a/b/c", 'canonpath and ..');
is(canonpath("$tmpdir/a/b/c/../../"), "$tmpdir/a", 'canonpath .. at end');
is(canonpath("$tmpdir/cbis/../"), "$tmpdir/cbis/..", 'canonpath .. after symlink');

is(resolve_symlink("$tmpdir/here/cbis"), "$tmpdir/here/a/b/c", 'resolve_symlink');
is(resolve_symlink("$tmpdir/tmp"), '/this/does/not/exist', 'resolve_symlink absolute');
is(resolve_symlink("$tmpdir/here"), $tmpdir, 'resolve_symlink .');

ok(!check_files_are_the_same("$tmpdir/here", $tmpdir), 'Symlink is not the same!');
ok(check_files_are_the_same("$tmpdir/here/a", "$tmpdir/a"), 'Same directory');

sub gen_hier_travbase {
    my $basedir = shift;

    make_path("$basedir/subdir");
    gen_file("$basedir/file");
    gen_file("$basedir/subdir/subfile");
    symlink 'file', "$basedir/symlink-file";
    symlink 'subdir/subfile', "$basedir/symlink-subfile";
}

my $travbase = "$tmpdir/travbase";
my $travbase_out = "$tmpdir/travbase-out";
my %travtype = (
    none => {
        fail => 0,
        gen => sub { },
    },
    dev_null => {
        fail => 0,
        gen => sub {
            my $basedir = shift;
            symlink '/dev/null', "$basedir/dev-null";
        },
    },
    dots => {
        fail => 0,
        gen => sub {
            my $basedir = shift;
            symlink 'aa..bb..cc', "$basedir/dots";
        },
    },
    rel => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            symlink '../../..', "$basedir/rel";
        },
    },
    abs => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            symlink '/etc', "$basedir/abs";
        },
    },
    loop => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            symlink 'self', "$basedir/self";
        },
    },
    enoent_rel => {
        fail => 0,
        gen => sub {
            my $basedir = shift;
            symlink 'not-existent', "$basedir/enoent-rel";
        },
    },
    enoent_abs => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            symlink '/not-existent', "$basedir/enoent-abs";
        },
    },
    enoent_indirect_rel => {
        fail => 0,
        gen => sub {
            my $basedir = shift;
            symlink 'not-existent', "$basedir/enoent-rel";
            symlink 'enoent-rel', "$basedir/enoent-indirect-rel";
        },
    },
    enoent_indirect_abs => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            symlink '/not-existent', "$basedir/enoent-abs";
            symlink realpath("$basedir/enoent-abs"), "$basedir/enoent-indirect-abs";
        },
    },
    base_in_none => {
        fail => 0,
        gen => sub {
            my $basedir = shift;
            rename $basedir, "$basedir-real";
            symlink 'base_in_none-real', $basedir;
        },
    },
    base_in_rel => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            rename $basedir, "$basedir-real";
            symlink 'base_in_rel-real', $basedir;
            symlink '../../..', "$basedir/rel";
        },
    },
    base_in_abs => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            rename $basedir, "$basedir-real";
            symlink 'base_in_abs-real', $basedir;
            symlink '/etc', "$basedir/abs";
        },
    },
    base_out_empty => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            rename $basedir, "$travbase_out/base_out_empty-disabled";
            symlink abs2rel("$travbase_out/base_out_empty", $travbase), $basedir;
            make_path("$travbase_out/base_out_empty");
        },
    },
    base_out_none => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            rename $basedir, "$travbase_out/base_out_none";
            symlink abs2rel("$travbase_out/base_out_none", $travbase), $basedir;
        },
    },
    base_out_rel => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            rename $basedir, "$travbase_out/base_out_rel";
            symlink abs2rel("$travbase_out/base_out_rel", $travbase), $basedir;
            symlink '../../..', "$basedir/rel";
        },
    },
    base_out_abs => {
        fail => 1,
        gen => sub {
            my $basedir = shift;
            rename $basedir, "$travbase_out/base_out_abs";
            symlink abs2rel("$travbase_out/base_out_abs", $travbase), $basedir;
            symlink '/etc', "$basedir/abs";
        },
    },
);

make_path($travbase_out);

foreach my $travtype (sort keys %travtype) {
    my $travdir = "$travbase/$travtype";

    gen_hier_travbase($travdir);
    $travtype{$travtype}->{gen}->($travdir);

    my $catch;
    eval {
        check_directory_traversal($travbase, $travdir);
        1;
    } or do {
        $catch = $@;
    };
    if ($travtype{$travtype}->{fail}) {
        ok($catch, "directory traversal type $travtype detected");
        note("traversal reason: $catch") if $catch;
    } else {
        ok(! $catch, "no directory traversal type $travtype");
        diag("error from check_directory_traversal => $catch") if $catch;
    }
}

is(get_pkg_root_dir("$tmpdir/a/b/c"), "$tmpdir/a", 'get_pkg_root_dir');
is(guess_pkg_root_dir("$tmpdir/a/b/c"), "$tmpdir/a", 'guess_pkg_root_dir');
is(relative_to_pkg_root("$tmpdir/a/b/c"), 'b/c', 'relative_to_pkg_root');

chdir($tmpdir);

is(get_pkg_root_dir('debian/a/b/c'), undef, 'get_pkg_root_dir undef');
is(relative_to_pkg_root('debian/a/b/c'), undef, 'relative_to_pkg_root undef');
is(guess_pkg_root_dir('debian/a/b/c'), 'debian/a', 'guess_pkg_root_dir fallback');
