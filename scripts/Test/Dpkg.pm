# Copyright © 2015 Guillem Jover <guillem@debian.org>
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

package Test::Dpkg;

use strict;
use warnings;

our $VERSION = '0.00';
our @EXPORT_OK = qw(
    all_po_files
    all_perl_files
    all_perl_modules
    test_get_po_dirs
    test_get_perl_dirs
    test_get_data_path
    test_get_temp_path
    test_needs_author
    test_needs_module
    test_needs_command
    test_needs_srcdir_switch
    test_neutralize_checksums
);
our %EXPORT_TAGS = (
    needs => [ qw(
        test_needs_author
        test_needs_module
        test_needs_command
        test_needs_srcdir_switch
    ) ],
    paths => [ qw(
        all_po_files
        all_perl_files
        all_perl_modules
        test_get_po_dirs
        test_get_perl_dirs
        test_get_data_path
        test_get_temp_path
    ) ],
);

use Exporter qw(import);
use Cwd;
use File::Find;
use File::Basename;
use File::Path qw(make_path);
use IPC::Cmd qw(can_run);
use Test::More;

my $test_mode;

BEGIN {
    $test_mode = $ENV{DPKG_TEST_MODE} // 'dpkg';
}

sub _test_get_caller_dir
{
    my (undef, $path, undef) = caller 1;

    $path =~ s{\.t$}{};
    $path =~ s{^\./}{};

    return $path;
}

sub test_get_data_path
{
    my $path = shift;

    if (defined $path) {
        my $srcdir;
        $srcdir = $ENV{srcdir} if $test_mode ne 'cpan';
        $srcdir ||= '.';
        return "$srcdir/$path";
    } else {
        return _test_get_caller_dir();
    }
}

sub test_get_temp_path
{
    my $path = shift // _test_get_caller_dir();
    $path = 't.tmp/' . fileparse($path);

    make_path($path);
    return $path;
}

sub test_get_po_dirs
{
    if ($test_mode eq 'cpan') {
        return qw();
    } else {
        return qw(po scripts/po dselect/po man/po);
    }
}

sub test_get_perl_dirs
{
    if ($test_mode eq 'cpan') {
        return qw(t lib);
    } else {
        return qw(t src/t lib utils/t scripts dselect);
    }
}

sub all_po_files
{
    my $filter = shift // qr/\.(?:po|pot)$/;
    my @files;
    my $scan_po_files = sub {
        push @files, $File::Find::name if m/$filter/;
    };

    find($scan_po_files, test_get_po_dirs());

    return @files;
}

sub all_perl_files
{
    my $filter = shift // qr/\.(?:PL|pl|pm|t)$/;
    my @files;
    my $scan_perl_files = sub {
        push @files, $File::Find::name if m/$filter/;
    };

    find($scan_perl_files, test_get_perl_dirs());

    return @files;
}

sub all_perl_modules
{
    return all_perl_files(qr/\.pm$/);
}

sub test_needs_author
{
    if (not $ENV{DPKG_DEVEL_MODE} and not $ENV{AUTHOR_TESTING}) {
        plan skip_all => 'developer test';
    }
}

sub test_needs_module
{
    my ($module, @imports) = @_;
    my ($package) = caller;

    require version;
    my $version = '';
    if (@imports >= 1 and version::is_lax($imports[0])) {
        $version = shift @imports;
    }

    eval qq{
        package $package;
        use $module $version \@imports;
        1;
    } or do {
        plan skip_all => "requires module $module $version";
    }
}

sub test_needs_command
{
    my $command = shift;

    if (not can_run($command)) {
        plan skip_all => "requires command $command";
    }
}

sub test_needs_srcdir_switch
{
    if (defined $ENV{srcdir}) {
        chdir $ENV{srcdir} or BAIL_OUT("cannot chdir to source directory: $!");
    }
}

sub test_neutralize_checksums
{
    my $filename = shift;
    my $filenamenew = "$filename.new";

    my $cwd = getcwd();
    open my $fhnew, '>', $filenamenew or die "cannot open new $filenamenew in $cwd: $!";
    open my $fh, '<', $filename or die "cannot open $filename in $cwd: $!";
    while (<$fh>) {
        s/^ ([0-9a-f]{32,}) [1-9][0-9]* /q{ } . $1 =~ tr{0-9a-f}{0}r . q{ 0 }/e;
        print { $fhnew } $_;
    }
    close $fh or die "cannot close $filename";
    close $fhnew or die "cannot close $filenamenew";

    rename $filenamenew, $filename or die "cannot rename $filenamenew to $filename";
}

1;
