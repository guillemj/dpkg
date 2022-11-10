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

plan tests => 10;

use_ok('Dpkg::OpenPGP');
use_ok('Dpkg::OpenPGP::ErrorCodes');

report_options(quiet_warnings => 1);

my $datadir = test_get_data_path();
my $tmpdir = test_get_temp_path();

my $openpgp = Dpkg::OpenPGP->new();

my ($reffile, $binfile, $ascfile);

$binfile = "$datadir/data-file";
$reffile = "$datadir/data-file.asc";

ok($openpgp->armor('ARMORED FILE', $binfile, "$tmpdir/data-file.asc") == OPENPGP_OK(),
    'armoring file not ASCII Armored');
ok(compare("$tmpdir/data-file.asc", $reffile) == 0,
    'armor binary file into OpenPGP ASCII Armor');
ok($openpgp->armor('ARMORED FILE', $reffile, "$tmpdir/data-file-rearmor.asc") == OPENPGP_OK(),
    'armoring file ASCII Armored');
ok(compare("$tmpdir/data-file-rearmor.asc", $reffile) == 0,
    'rearmor binary file into OpenPGP ASCII Armor');

$ascfile = "$tmpdir/data-file.asc";

ok($openpgp->armor('ARMORED FILE', $binfile, $ascfile) == OPENPGP_OK(),
    'armoring succeeded');
ok(compare($ascfile, $reffile) == 0, 'armor binary file into OpenPGP ASCII Armor');

$reffile = "$datadir/data-file";
$ascfile = "$datadir/data-file.asc";
$binfile = "$tmpdir/data-file";

ok($openpgp->dearmor('ARMORED FILE', $ascfile, $binfile) == OPENPGP_OK(),
   'dearmoring succeeded');
ok(compare($binfile, $reffile) == 0, 'dearmor OpenPGP ASCII Armor into binary file');

# TODO: Add actual test cases.

1;
