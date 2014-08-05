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
use Test::Dpkg qw(test_neutralize_checksums);

use File::Spec::Functions qw(rel2abs);
use File::Compare;
use File::Path qw(make_path);

use Dpkg::IPC;
use Dpkg::Substvars;

my $srcdir = rel2abs($ENV{srcdir} || '.');
my $datadir = "$srcdir/t/dpkg_source";
my $tmpdir = 't.tmp/dpkg_source';

$ENV{$_} = rel2abs($ENV{$_}) foreach qw(DPKG_DATADIR DPKG_ORIGINS_DIR);

# Delete variables that can affect the tests.
delete $ENV{SOURCE_DATE_EPOCH};

make_path($tmpdir);

chdir $tmpdir;

my $tmpl_format = <<'TMPL_FORMAT';
3.0 (native)
TMPL_FORMAT

my $tmpl_changelog = <<'TMPL_CHANGELOG';
${source-name} (${source-version}) ${suite}; urgency=${urgency}

  * Test package.

 -- ${maintainer}  Sat, 05 Jul 2014 21:11:22 +0200
TMPL_CHANGELOG

my $tmpl_control = <<'TMPL_CONTROL';
Source: ${source-name}
Section: ${source-section}
Priority: ${source-priority}
Maintainer: ${maintainer}
Standards-Version: 1.0
Testsuite: ${source-testsuite}

Package: test-binary
Architecture: all
Description: test package
TMPL_CONTROL

my %default_substvars = (
    'source-name' => 'test-source',
    'source-version' => 0,
    'source-section' => 'test',
    'source-priority' => 'optional',
    'source-testsuite' => 'autopkgtest',
    'suite' => 'unstable',
    'urgency' => 'low',
    'maintainer' => 'Dpkg Developers <debian-dpkg@lists.debian.org>',
);

sub gen_from_tmpl
{
    my ($pathname, $tmpl, $substvars) = @_;

    open my $fh, '>', $pathname or die;
    print { $fh } $substvars->substvars($tmpl);
    close $fh or die;
}

sub gen_source
{
    my (%options) = @_;

    my $substvars = Dpkg::Substvars->new();
    foreach my $var (%default_substvars) {
        my $value = $options{$var} // $default_substvars{$var};

        $substvars->set_as_auto($var, $value);
    }

    my $source = $substvars->get('source-name');
    my $version = $substvars->get('source-version');
    my $dirname = "$source-$version";

    make_path("$dirname/debian/source");

    gen_from_tmpl("$dirname/debian/source/format", $tmpl_format, $substvars);
    gen_from_tmpl("$dirname/debian/changelog", $tmpl_changelog, $substvars);
    gen_from_tmpl("$dirname/debian/control", $tmpl_control, $substvars);

    if (defined $options{'control-test'}) {
        make_path("$dirname/debian/tests");
        gen_from_tmpl("$dirname/debian/tests/control", $options{'control-test'}, $substvars);
    }

    return $dirname;
}

sub test_diff
{
    my $filename = shift;

    my $expected_file = "$datadir/$filename";
    my $generated_file =  $filename;

    test_neutralize_checksums($generated_file);

    my $res = compare($expected_file, $generated_file);
    if ($res) {
        system "diff -u $expected_file $generated_file >&2";
    }
    ok($res == 0, "generated file matches expected one ($expected_file)");
}

sub test_build_source
{
    my ($name) = shift;

    spawn(exec => [ "$srcdir/dpkg-source.pl", '-b', $name ],
          error_to_file => '/dev/null',
          wait_child => 1, nocheck => 1);

    my $basename = $name =~ tr/-/_/r;

    test_diff("$basename.dsc");
}

my $dirname;

$dirname = gen_source('source-name' => 'testsuite',
                      'source-version' => 0,
                      'control-test' => '');
test_build_source($dirname);

$dirname = gen_source('source-name' => 'testsuite',
                      'source-version' => 1,
                      'control-test' => '');
test_build_source($dirname);

$dirname = gen_source('source-name' => 'testsuite',
                      'source-version' => 2,
                      'source-testsuite' => 'smokepkgtest, unitpkgtest, funcpkgtest',
                      'control-test' => '');
test_build_source($dirname);

$dirname = gen_source('source-name' => 'testsuite',
                      'source-version' => 3);
test_build_source($dirname);

1;
