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

use Test::More tests => 23;

use IO::String;

BEGIN {
    use_ok('Dpkg::Control');
    use_ok('Dpkg::Control::Info');
}

my $srcdir = $ENV{srcdir} || '.';
my $datadir = $srcdir . '/t/Dpkg_Control';

sub parse_dsc {
    my $path = shift;

    my $dsc = Dpkg::Control->new(type => CTRL_PKG_SRC);
    eval {
        $dsc->load($path);
        1;
    } or return;

    return $dsc;
}

my $c = Dpkg::Control::Info->new("$datadir/control-1");

my $io = IO::String->new();
$c->output($io);
my $value = ${$io->string_ref()};
my $expected = 'Source: mysource
Numeric-Field: 0
My-Field-One: myvalue1
My-Field-Two: myvalue2
Long-Field: line1
 line 2 line 2 line 2
 .
   line 3 line 3 line 3
 ..
 line 4
Empty-Field:

Package: mypackage1
Architecture: any
Depends: libc6

Package: mypackage2
Architecture: all
Depends: hello

Package: mypackage3
Architecture: all
Depends: hello
Description: short one
 long one
 very long one
';
is($value, $expected, "Dump of $datadir/control-1");

my $src = $c->get_source();
is($src, $c->[0], 'array representation of Dpkg::Control::Info 1/2');
is($src->{'numeric-field'}, '0', 'Numeric 0 value parsed correctly');
is($src->{'my-field-one'}, 'myvalue1', 'Access field through badly capitalized field name');
is($src->{'long-field'},
'line1
line 2 line 2 line 2

  line 3 line 3 line 3
.
line 4', 'Get multi-line field');
is($src->{'Empty-field'}, '', 'Get empty field');

my $pkg = $c->get_pkg_by_idx(1);
is($pkg, $c->[1], 'array representation of Dpkg::Control::Info 2/2');
is($pkg->{package}, 'mypackage1', 'Name of first package');

$pkg = $c->get_pkg_by_name('mypackage3');
is($pkg->{package}, 'mypackage3', 'Name of third package');
is($pkg->{Depends}, 'hello', 'Name of third package');

$pkg = $c->get_pkg_by_idx(2);
$io = IO::String->new();
$pkg->output($io);

is(${$io->string_ref()},
'Package: mypackage2
Architecture: all
Depends: hello
', "Dump of second binary package of $datadir/control-1");

# Check OpenPGP armored signatures in source control files

my $dsc;

$dsc = parse_dsc("$datadir/bogus-unsigned.dsc");
is($dsc, undef, 'Unsigned .dsc w/ OpenPGP armor');

$dsc = parse_dsc("$datadir/bogus-armor-no-sig.dsc");
is($dsc, undef, 'Signed .dsc w/ OpenPGP armor missing signature');

$dsc = parse_dsc("$datadir/bogus-armor-trail.dsc");
is($dsc, undef, 'Signed .dsc w/ bogus OpenPGP armor trailer');

$dsc = parse_dsc("$datadir/bogus-armor-inline.dsc");
is($dsc, undef, 'Signed .dsc w/ bogus OpenPGP inline armor');

$dsc = parse_dsc("$datadir/bogus-armor-double.dsc");
ok(defined $dsc, 'Signed .dsc w/ two OpenPGP armor signatures');
is($dsc->{Source}, 'pass', 'Signed spaced .dsc package name');

$dsc = parse_dsc("$datadir/bogus-armor-spaces.dsc");
ok(defined $dsc, 'Signed .dsc w/ spaced OpenPGP armor');
is($dsc->{Source}, 'pass', 'Signed spaced .dsc package name');

$dsc = parse_dsc("$datadir/bogus-armor-nested.dsc");
ok(defined $dsc, 'Signed .dsc w/ nested OpenPGP armor');
is($dsc->{Source}, 'pass', 'Signed nested .dsc package name');
