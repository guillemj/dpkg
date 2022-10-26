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
use Test::Dpkg qw(:paths);

BEGIN {
    use_ok('Dpkg::File');
}

my $datadir = test_get_data_path();

my ($data, $data_ref, $data_fh);

$data = file_slurp("$datadir/slurp-me");
$data_ref = <<'DATA';
first line
next line
final line
DATA
is($data, $data_ref, 'slurped data');

open $data_fh, '<', "$datadir/slurp-me"
    or die "cannot open $datadir/slurp-me for reading: $!";
my $discard = <$data_fh>;
$data = file_slurp($data_fh);
close $data_fh;
$data_ref = <<'DATA';
next line
final line
DATA
is($data, $data_ref, 'slurped partial data');

$data = undef;
eval {
    $data = file_slurp("$datadir/non-existent");
};
ok($@, 'cannot slurp missing file');

1;
