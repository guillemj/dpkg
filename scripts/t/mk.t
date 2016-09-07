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

use Test::More tests => 5;
use File::Spec::Functions qw(rel2abs);

use Dpkg ();
use Dpkg::ErrorHandling;
use Dpkg::IPC;
use Dpkg::Vendor;

my $srcdir = $ENV{srcdir} || '.';
my $datadir = "$srcdir/t/mk";

# Turn these into absolute names so that we can safely switch to the test
# directory with «make -C».
$ENV{$_} = rel2abs($ENV{$_}) foreach qw(srcdir DPKG_DATADIR DPKG_ORIGINS_DIR);

# Any paralellization from the parent should be ignored, we are testing
# the makefiles serially anyway.
delete $ENV{MAKEFLAGS};

# Delete other variables that can affect the tests.
delete $ENV{$_} foreach grep { m/^DEB_/ } keys %ENV;

$ENV{DEB_BUILD_PATH} = rel2abs($datadir);

sub test_makefile {
    my $makefile = shift;

    spawn(exec => [ $Dpkg::PROGMAKE, '-C', $datadir, '-f', $makefile ],
          wait_child => 1, nocheck => 1);
    ok($? == 0, "makefile $makefile computes all values correctly");
}

sub cmd_get_vars {
    my (@cmd) = @_;
    my %var;

    open my $cmd_fh, '-|', @cmd or subprocerr($cmd[0]);
    while (<$cmd_fh>) {
        chomp;
        my ($key, $value) = split /=/, $_, 2;
        $var{$key} = $value;
    }
    close $cmd_fh or subprocerr($cmd[0]);

    return %var;
}

# Test makefiles.

my %arch = cmd_get_vars("$srcdir/dpkg-architecture.pl", '-f');

delete $ENV{$_} foreach keys %arch;
$ENV{"TEST_$_"} = $arch{$_} foreach keys %arch;
test_makefile('architecture.mk');
$ENV{$_} = $arch{$_} foreach keys %arch;
test_makefile('architecture.mk');

my %buildflag = cmd_get_vars("$srcdir/dpkg-buildflags.pl");

delete $ENV{$_} foreach keys %buildflag;
$ENV{"TEST_$_"} = $buildflag{$_} foreach keys %buildflag;
test_makefile('buildflags.mk');

test_makefile('pkg-info.mk');

test_makefile('vendor.mk');

1;
