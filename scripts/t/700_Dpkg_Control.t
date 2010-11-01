# -*- mode: cperl;-*-
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use Test::More tests => 11;

use strict;
use warnings;
use IO::String;

use_ok('Dpkg::Control::Info');

my $srcdir = $ENV{srcdir} || '.';
my $datadir = $srcdir . '/t/700_Dpkg_Control';

my $c = Dpkg::Control::Info->new("$datadir/control-1");

my $io = IO::String->new();
$c->output($io);
my $value = ${$io->string_ref()};
my $expected = 'Source: mysource
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
Depends: libc6

Package: mypackage2
Depends: hello

Package: mypackage3
Depends: hello
Description: short one
 long one
 very long one
';
is($value, $expected, "Dump of $datadir/control-1");

my $src = $c->get_source();
is($src, $c->[0], "array representation of Dpkg::Control::Info 1/2");
is($src->{'my-field-one'}, 'myvalue1', "Access field through badly capitalized field name");
is($src->{'long-field'}, 
'line1
line 2 line 2 line 2

  line 3 line 3 line 3
.
line 4', "Get multi-line field");
is($src->{'Empty-field'}, "", "Get empty field");

my $pkg = $c->get_pkg_by_idx(1);
is($pkg, $c->[1], "array representation of Dpkg::Control::Info 2/2");
is($pkg->{package}, 'mypackage1', 'Name of first package');

$pkg = $c->get_pkg_by_name("mypackage3");
is($pkg->{package}, 'mypackage3', 'Name of third package');
is($pkg->{Depends}, 'hello', 'Name of third package');

$pkg = $c->get_pkg_by_idx(2);
$io = IO::String->new();
$pkg->output($io);

is(${$io->string_ref()},
'Package: mypackage2
Depends: hello
', "Dump of second binary package of $datadir/control-1");
