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

plan tests => 6;

use_ok('Dpkg::OpenPGP');

report_options(quiet_warnings => 1);

my $datadir = test_get_data_path();
my $tmpdir = test_get_temp_path();
my $ascfile;

$ascfile = "$tmpdir/package_1.0.orig.tar.enoent";
is(openpgp_sig_to_asc("$datadir/nonexistent", $ascfile),
   undef, 'no conversion of inexistent file');

$ascfile = "$tmpdir/package_1.0.orig.tar.sig2asc";
is(openpgp_sig_to_asc("$datadir/package_1.0.orig.tar.sig", $ascfile),
   $ascfile, 'conversion from binary sig to armored asc');

ok(compare($ascfile, "$datadir/package_1.0.orig.tar.asc") == 0,
   'binary signature converted to OpenPGP ASCII Armor');

# Grab the output messages.
eval {
    $ascfile = "$tmpdir/package_1.0.orig.tar.asc2asc";
    is(openpgp_sig_to_asc("$datadir/package_1.0.orig.tar.asc", $ascfile),
       $ascfile, 'copy instead of converting already armored input');
};

ok(compare($ascfile, "$datadir/package_1.0.orig.tar.asc") == 0,
   'OpenPGP ASCII Armor copied to destination');

# TODO: Add actual test cases.

1;
