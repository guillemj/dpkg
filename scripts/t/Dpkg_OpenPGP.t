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

plan tests => 5;

use_ok('Dpkg::OpenPGP');

report_options(quiet_warnings => 1);

my $datadir = test_get_data_path();
my $tmpdir = test_get_temp_path();

my ($reffile, $binfile, $ascfile);

$binfile = "$datadir/data-file";
$reffile = "$datadir/data-file.asc";

ok(!Dpkg::OpenPGP::is_armored($binfile), 'file not ASCII Armored');
ok(Dpkg::OpenPGP::is_armored($reffile), 'file ASCII Armored');

$ascfile = "$tmpdir/data-file.asc";

Dpkg::OpenPGP::armor('ARMORED FILE', $binfile, $ascfile);
ok(compare($ascfile, $reffile) == 0, 'armor binary file into OpenPGP ASCII Armor');

$reffile = "$datadir/data-file";
$ascfile = "$datadir/data-file.asc";
$binfile = "$tmpdir/data-file";

Dpkg::OpenPGP::dearmor('ARMORED FILE', $ascfile, $binfile);
ok(compare($binfile, $reffile) == 0, 'dearmor OpenPGP ASCII Armor into binary file');

# TODO: Add actual test cases.

1;
