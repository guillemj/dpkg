#!/usr/bin/perl
#
# Copyright © 2016 Guillem Jover <guillem@debian.org>
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
use version;

use Test::More tests => 6;
use Cwd;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use File::Basename;
use File::Find;

use Dpkg::IPC;

my $srcdir = $ENV{srcdir} || '.';
my $builddir = $ENV{builddir} || '.';
my $tmpdir = 't.tmp/t-tree';

# Set a known umask.
umask 0022;

sub make_file {
    my ($pathname) = @_;

    open my $fh, '>>', $pathname or die "cannot touch $pathname: $!";
    close $fh;
}

# Popullate the tree hierarchy.
sub make_tree {
    my ($dirtree) = @_;
    my $cwd = cwd();

    make_path($dirtree);
    chdir $dirtree;

    # Deep tree.
    make_path('aaaa/aaaa/aaaa/aaaa/');
    make_file('aaaa/aaaa/aaaa/aaaa/abcde');
    make_file('aaaa/aaaa/aaaa/aaaa/ddddd');
    make_file('aaaa/aaaa/aaaa/aaaa/wwwwa');
    make_file('aaaa/aaaa/aaaa/aaaa/wwwwz');
    make_file('aaaa/aaaa/aaaa/aaaa/zzzzz');

    # Shallow tree.
    make_path('bbbb/');
    make_file('bbbb/abcde');
    make_file('bbbb/ddddd');
    make_file('bbbb/wwwwa');
    make_file('bbbb/wwwwz');
    make_file('bbbb/zzzzz');

    # Popullated tree.
    make_path('cccc/aa/aa/aa/');
    make_path('cccc/aa/aa/bb/aa/');
    make_file('cccc/aa/aa/bb/aa/file-a');
    make_file('cccc/aa/aa/bb/aa/file-z');
    make_path('cccc/aa/bb/');
    make_path('cccc/bb/aa/');
    make_path('cccc/bb/bb/aa/aa/');
    make_file('cccc/bb/bb/aa/aa/file-a');
    make_file('cccc/bb/bb/aa/aa/file-z');
    make_path('cccc/bb/bb/bb/');
    make_file('cccc/bb/bb/bb/file-w');
    make_path('cccc/cc/aa/');
    make_path('cccc/cc/bb/aa/');
    make_file('cccc/cc/bb/aa/file-t');
    make_path('cccc/cc/bb/bb/');
    make_file('cccc/cc/bb/bb/file-x');
    make_path('cccc/cc/cc/');
    make_path('cccc/dd/aa/aa/aa/');
    make_file('cccc/dd/aa/aa/aa/file-y');
    make_path('cccc/dd/aa/aa/bb/');
    make_file('cccc/dd/aa/aa/bb/file-o');
    make_path('cccc/dd/aa/bb/aa/');
    make_file('cccc/dd/aa/bb/aa/file-k');
    make_path('cccc/dd/aa/bb/bb/');
    make_file('cccc/dd/aa/bb/bb/file-l');
    make_path('cccc/dd/aa/cc/aa/');
    make_file('cccc/dd/aa/cc/aa/file-s');
    make_path('cccc/dd/aa/cc/bb/');
    make_file('cccc/dd/aa/cc/bb/file-u');

    # Tree with symlinks cycles.
    make_path('llll/self/');
    make_file('llll/file');
    symlink '..', 'llll/self/loop';
    make_path('llll/real/');
    make_file('llll/real/file-r');
    symlink '../virt', 'llll/real/loop';
    make_path('llll/virt/');
    make_file('llll/virt/file-v');
    symlink '../real', 'llll/virt/loop';

    chdir $cwd;
}

sub test_treewalker {
    my $stdout;
    my $stderr;
    my $dirtree = $tmpdir;

    # Check generated tarballs.
    foreach my $type (qw(full skip)) {
        my @paths;

        make_tree($dirtree);

        find({ no_chdir => 1, wanted => sub {
                   return if $type eq 'skip' and m{^\Q$dirtree\E/cccc};
                   push @paths, s{\./}{}r;
               },
             }, $dirtree);

        my $expected;

        foreach my $path (sort @paths) {
            lstat $path;

            my $ptype;
            if (-f _) {
                $ptype = 'f';
            } elsif (-l _) {
                $ptype = 'l';
            } elsif (-d _) {
                $ptype = 'd';
            }
            my $pname = basename($path);
            my $pvirt = $path =~ s{\Q$dirtree\E/?}{}r;

            $expected .= "T=$ptype N=$pname V=$pvirt R=$path\n";
        }

        $ENV{TREEWALK_SKIP} = $type eq 'skip' ? "$dirtree/cccc" : undef;

        spawn(exec => [ './t-treewalk', $dirtree ],
              nocheck => 1, to_string => \$stdout, to_error => \$stderr);
        ok($? == 0, "tree walker $type should succeed");
        is($stderr, undef, "tree walker $type stderr is empty");
        is($stdout, $expected, "tree walker $type is ok");
    }
}

test_treewalker();
