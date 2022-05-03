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

use Test::More tests => 4;

use File::Spec;
use File::Path qw(make_path rmtree);

BEGIN {
    use_ok('Dpkg::Source::Archive');
}

use Dpkg;

my $tmpdir = 't.tmp/Dpkg_Source_Archive';

rmtree($tmpdir);

sub test_touch
{
    my ($name, $data) = @_;

    open my $fh, '>', $name
        or die "cannot touch file $name\n";
    print { $fh } $data if $data;
    close $fh;
}

sub test_path_escape
{
    my $name = shift;

    my $treedir = File::Spec->rel2abs("$tmpdir/$name-tree");
    my $overdir = File::Spec->rel2abs("$tmpdir/$name-overlay");
    my $outdir = "$tmpdir/$name-out";
    my $expdir = "$tmpdir/$name-exp";

    # This is the base directory, where we are going to be extracting stuff
    # into, which include traps.
    make_path("$treedir/subdir-a");
    test_touch("$treedir/subdir-a/file-a");
    test_touch("$treedir/subdir-a/file-pre-a");
    make_path("$treedir/subdir-b");
    test_touch("$treedir/subdir-b/file-b");
    test_touch("$treedir/subdir-b/file-pre-b");
    symlink File::Spec->abs2rel($outdir, $treedir), "$treedir/symlink-escape";
    symlink File::Spec->abs2rel("$outdir/nonexistent", $treedir), "$treedir/symlink-nonexistent";
    symlink "$treedir/file", "$treedir/symlink-within";
    test_touch("$treedir/supposed-dir");

    # This is the overlay directory, which we'll pack and extract over the
    # base directory.
    make_path($overdir);
    make_path("$overdir/subdir-a/aa");
    test_touch("$overdir/subdir-a/aa/file-aa", 'aa');
    test_touch("$overdir/subdir-a/file-a", 'a');
    make_path("$overdir/subdir-b/bb");
    test_touch("$overdir/subdir-b/bb/file-bb", 'bb');
    test_touch("$overdir/subdir-b/file-b", 'b');
    make_path("$overdir/symlink-escape");
    test_touch("$overdir/symlink-escape/escaped-file", 'escaped');
    test_touch("$overdir/symlink-nonexistent", 'nonexistent');
    make_path("$overdir/symlink-within");
    make_path("$overdir/supposed-dir");
    test_touch("$overdir/supposed-dir/supposed-file", 'something');

    # Generate overlay tar.
    system('tar', '-cf', "$overdir.tar", '-C', $overdir, qw(
        subdir-a subdir-b
        symlink-escape/escaped-file symlink-nonexistent symlink-within
        supposed-dir
        )) == 0
        or die "cannot create overlay tar archive\n";

   # This is the expected directory, which we'll be comparing against.
    make_path($expdir);
    system('cp', '-a', $overdir, $expdir) == 0
        or die "cannot copy overlay hierarchy into expected directory\n";

    # Store the expected and out reference directories into a tar to compare
    # its structure against the result reference.
    system('tar', '-cf', "$expdir.tar", '-C', $overdir, qw(
        subdir-a subdir-b
        symlink-escape/escaped-file symlink-nonexistent symlink-within
        supposed-dir
        ), '-C', $treedir, qw(
        subdir-a/file-pre-a
        subdir-b/file-pre-b
        )) == 0
        or die "cannot create expected tar archive\n";

    # This directory is supposed to remain empty, anything inside implies a
    # directory traversal.
    make_path($outdir);

    my $warnseen;
    local $SIG{__WARN__} = sub { $warnseen = $_[0] };

    # Perform the extraction.
    my $tar = Dpkg::Source::Archive->new(filename => "$overdir.tar");
    $tar->extract($treedir, in_place => 1);

    # Store the result into a tar to compare its structure against a reference.
    system('tar', '-cf', "$treedir.tar", '-C', $treedir, '.');

    # Check results
    ok(length $warnseen && $warnseen =~ m/points outside source root/,
       'expected warning seen');
    ok(system('tar', '--compare', '-f', "$expdir.tar", '-C', $treedir) == 0,
       'expected directory matches');
    ok(! -e "$outdir/escaped-file",
       'expected output directory is empty, directory traversal');
}

test_path_escape('in-place');

# TODO: Add actual test cases.

1;
