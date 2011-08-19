# -*- mode: cperl -*-
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

use Test::More tests => 13;

use strict;
use warnings;

use_ok('Dpkg::Compression');
use_ok('Dpkg::Compression::FileHandle');

my $tmpdir = "t.tmp/850_Dpkg_Compression";
mkdir $tmpdir;
my @lines = ("One\n", "Two\n", "Three\n");
my $fh;

sub test_write {
    my ($filename, $check_result) = @_;

    $fh = Dpkg::Compression::FileHandle->new();
    open $fh, ">", $filename or die "open failed";
    print $fh $lines[0];
    syswrite($fh, $lines[1]);
    printf $fh "%s", $lines[2];
    close $fh or die "close failed";

    &$check_result($filename, "std functions");

    unlink $filename or die "cannot unlink $filename";

    $fh = Dpkg::Compression::FileHandle->new();
    $fh->open($filename, "w");
    $fh->print($lines[0]);
    $fh->write($lines[1], length($lines[1]));
    $fh->printf("%s", $lines[2]);
    $fh->close() or die "close failed";

    &$check_result($filename, "IO::Handle methods");
}

sub check_uncompressed {
    my ($filename, $method) = @_;
    open(READ, "<", $filename) or die "cannot read $filename";
    my @read = <READ>;
    close READ or die "cannot close";
    is_deeply(\@lines, \@read, "$filename correctly written ($method)");
}

sub check_compressed {
    my ($filename, $method) = @_;
    open(READ, "-|", "zcat $tmpdir/myfile.gz") or die "cannot fork zcat";
    my @read = <READ>;
    close READ or die "cannot close";
    is_deeply(\@lines, \@read, "$filename correctly written ($method)");
}

sub test_read {
    my ($filename) = @_;

    $fh = Dpkg::Compression::FileHandle->new();
    open($fh, "<", $filename) or die "open failed";
    my @read = <$fh>;
    close $fh or die "close failed";

    is_deeply(\@lines, \@read, "$filename correctly read (std functions)");

    @read = ();
    $fh = Dpkg::Compression::FileHandle->new();
    $fh->open($filename, "r") or die "open failed";
    @read = $fh->getlines();
    $fh->close() or die "close failed";

    is_deeply(\@lines, \@read, "$filename correctly read (IO::Handle methods)");
}

# Test changing the default compression levels
my $old_level = compression_get_default_level();
compression_set_default_level(1);
is(compression_get_default_level(), 1, "change default compression level");
compression_set_default_level(5);
is(compression_get_default_level(), 5, "change default compression level");
compression_set_default_level(undef);
is(compression_get_default_level(), $old_level, "reset default compression level");

# Test write on uncompressed file
test_write("$tmpdir/myfile", \&check_uncompressed);

# Test write on compressed file
test_write("$tmpdir/myfile.gz", \&check_compressed);

# Test read on uncompressed file
test_read("$tmpdir/myfile");

# Test read on compressed file
test_read("$tmpdir/myfile.gz");
