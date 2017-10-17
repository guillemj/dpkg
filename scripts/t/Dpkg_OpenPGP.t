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
use Test::Dpkg qw(:paths :needs);

use File::Compare;

use Dpkg::ErrorHandling;

test_needs_command('gpg');

plan tests => 3;

use_ok('Dpkg::OpenPGP');

report_options(quiet_warnings => 1);

my $datadir = test_get_data_path('t/Dpkg_OpenPGP');
my $tmpdir = 't.tmp/Dpkg_OpenPGP';

mkdir $tmpdir;

openpgp_sig_to_asc("$datadir/package_1.0.orig.tar.sig",
                   "$tmpdir/package_1.0.orig.tar.sig2asc");

ok(compare("$tmpdir/package_1.0.orig.tar.sig2asc",
           "$datadir/package_1.0.orig.tar.asc") == 0,
   'binary signature converted to OpenPGP ASCII Armor');

# Grab the output messages.
eval {
    openpgp_sig_to_asc("$datadir/package_1.0.orig.tar.asc",
                       "$tmpdir/package_1.0.orig.tar.asc2asc");
};

ok(compare("$tmpdir/package_1.0.orig.tar.asc2asc",
           "$datadir/package_1.0.orig.tar.asc") == 0,
   'OpenPGP ASCII Armor copied to destination');

# TODO: Add actual test cases.

1;
