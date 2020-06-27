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

use Cwd;
use File::Spec::Functions qw(rel2abs);
use File::Path qw(make_path);

use Dpkg::IPC;

plan tests => 48;

my $srcdir = rel2abs($ENV{srcdir} || '.');
my $tmpdir = rel2abs(test_get_temp_path());

# Delete variables that can affect the tests.
delete $ENV{DPKG_ROOT};

sub gen_file
{
    my ($pathname) = @_;

    open my $fh, '>', $pathname or BAIL_OUT("cannot create file $pathname");
    close $fh;
}

sub gen_hier
{
    my $curdir = getcwd();

    chdir $tmpdir;

    make_path('aa/bb/cc');
    make_path('zz/yy/xx');
    make_path('usr/bin');

    gen_file('aa/bb/cc/file');
    symlink('aa/bb/cc/file', 'zz/yy/xx/symlink-rel');
    symlink('/aa/bb/cc/file', 'zz/yy/xx/symlink-abs');
    gen_file('usr/bin/a-shell');
    symlink('/usr/bin/a-shell', 'usr/bin/sh');

    chdir $curdir;
}

sub test_realpath
{
    my ($pathname, $realpath, $root) = @_;
    my ($stderr, $stdout);
    $root //= q{};

    spawn(
        exec => [ $ENV{SHELL}, "$srcdir/dpkg-realpath.sh", $pathname ],
        env => {
            DPKG_ROOT => $root,
            DPKG_DATADIR => rel2abs($srcdir),
        },
        error_to_string => \$stderr,
        to_string => \$stdout,
        wait_child => 1,
        nocheck => 1,
    );

    ok($? == 0, "dpkg-realpath $pathname succeeded");
    diag($stderr) unless $? == 0;

    chomp $stdout;

    is($stdout, $realpath,
       "resolved realpath for $pathname matches $realpath with root='$root'");
}

gen_hier();

# Relative paths
my $curdir = getcwd();
chdir $tmpdir;

test_realpath('aa/bb/cc', "$tmpdir/aa/bb/cc");
test_realpath('zz/yy/xx', "$tmpdir/zz/yy/xx");
test_realpath('usr/bin', "$tmpdir/usr/bin");
test_realpath('aa/bb/cc/file', "$tmpdir/aa/bb/cc/file");
test_realpath('zz/yy/xx/symlink-rel', "$tmpdir/zz/yy/xx/aa/bb/cc/file");
test_realpath('zz/yy/xx/symlink-abs', '/aa/bb/cc/file');
test_realpath('usr/bin/a-shell', "$tmpdir/usr/bin/a-shell");
test_realpath('usr/bin/sh', '/usr/bin/a-shell');

chdir $curdir;

# Absolute paths
test_realpath("$tmpdir/aa/bb/cc", "$tmpdir/aa/bb/cc");
test_realpath("$tmpdir/zz/yy/xx", "$tmpdir/zz/yy/xx");
test_realpath("$tmpdir/usr/bin", "$tmpdir/usr/bin");
test_realpath("$tmpdir/aa/bb/cc/file", "$tmpdir/aa/bb/cc/file");
test_realpath("$tmpdir/zz/yy/xx/symlink-rel", "$tmpdir/zz/yy/xx/aa/bb/cc/file");
test_realpath("$tmpdir/zz/yy/xx/symlink-abs", '/aa/bb/cc/file');
test_realpath("$tmpdir/usr/bin/a-shell", "$tmpdir/usr/bin/a-shell");
test_realpath("$tmpdir/usr/bin/sh", '/usr/bin/a-shell');

# Chrooted paths
test_realpath('/aa/bb/cc', '/aa/bb/cc', $tmpdir);
test_realpath('/zz/yy/xx', '/zz/yy/xx', $tmpdir);
test_realpath('/usr/bin', '/usr/bin', $tmpdir);
test_realpath('/aa/bb/cc/file', '/aa/bb/cc/file', $tmpdir);
test_realpath('/zz/yy/xx/symlink-rel', '/zz/yy/xx/aa/bb/cc/file', $tmpdir);
test_realpath('/zz/yy/xx/symlink-abs', '/aa/bb/cc/file', $tmpdir);
test_realpath('/usr/bin/a-shell', '/usr/bin/a-shell', $tmpdir);
test_realpath('/usr/bin/sh', '/usr/bin/a-shell', $tmpdir);

1;
