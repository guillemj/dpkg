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

use Test::More tests => 15;

use_ok('Dpkg::Dist::Files');

my $srcdir = $ENV{srcdir} // '.';
my $datadir = $srcdir . '/t/Dpkg_Dist_Files';

my $expected;
my %expected = (
    'pkg-templ_1.2.3_arch.type' => {
        filename => 'pkg-templ_1.2.3_arch.type',
        package => 'pkg-templ',
        package_type => 'type',
        version => '1.2.3',
        arch => 'arch',
        section => 'section',
        priority => 'priority',
    },
    'pkg-arch_2.0.0_amd64.deb' => {
        filename => 'pkg-arch_2.0.0_amd64.deb',
        package => 'pkg-arch',
        package_type => 'deb',
        version => '2.0.0',
        arch => 'amd64',
        section => 'admin',
        priority => 'required',
    },
    'pkg-indep_0.0.1-2_all.deb' => {
        filename => 'pkg-indep_0.0.1-2_all.deb',
        package => 'pkg-indep',
        package_type => 'deb',
        version => '0.0.1-2',
        arch => 'all',
        section => 'net',
        priority => 'standard',
    },
    'other_0.txt' => {
        filename => 'other_0.txt',
        section => 'text',
        priority => 'optional',
    },
    'BY-HAND-file' => {
        filename => 'BY-HAND-file',
        section => 'webdocs',
        priority => 'optional',
    },
);

my $dist = Dpkg::Dist::Files->new();
$dist->load("$datadir/files-byhand") or error('cannot parse file');

$expected = <<'FILES';
BY-HAND-file webdocs optional
other_0.txt text optional
pkg-arch_2.0.0_amd64.deb admin required
pkg-indep_0.0.1-2_all.deb net standard
pkg-templ_1.2.3_arch.type section priority
FILES

is($dist->output(), $expected, 'Parsed dist file');
foreach my $f ($dist->get_files()) {
    my $filename = $f->{filename};

    is_deeply($f, $expected{$filename},
              "Detail for individual dist file $filename, via get_files()");

    my $fs = $dist->get_file($filename);
    is_deeply($fs, $expected{$filename},
              "Detail for individual dist file $filename, via get_file()");
}

$expected = <<'FILES';
BY-HAND-file webdocs optional
added-on-the-fly void wish
other_0.txt text optional
pkg-arch_2.0.0_amd64.deb void imperative
pkg-templ_1.2.3_arch.type section priority
FILES

$dist->add_file('added-on-the-fly', 'void', 'wish');
$dist->add_file('pkg-arch_2.0.0_amd64.deb', 'void', 'imperative');
$dist->del_file('pkg-indep_0.0.1-2_all.deb');
is($dist->get_file('unknown'), undef, 'Get unknown file');
is($dist->get_file('pkg-indep_0.0.1-2_all.deb'), undef, 'Get deleted file');
is($dist->output(), $expected, 'Modified dist object');

1;
