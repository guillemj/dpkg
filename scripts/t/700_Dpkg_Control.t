# -*- mode: cperl;-*-

use Test::More tests => 9;

use strict;
use warnings;
use IO::String;

use_ok('Dpkg::Control');

my $srcdir = $ENV{srcdir} || '.';
$srcdir .= '/t/700_Dpkg_Control';

my $c = Dpkg::Control->new("$srcdir/control-1");

my $io = IO::String->new();
$c->dump($io);
is(${$io->string_ref()},
'Source: mysource
My-Field-One: myvalue1
My-Field-Two: myvalue2
Long-Field: line1
 line 2 line 2 line 2
 line 3 line 3 line 3
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
', "Dump of $srcdir/control-1");

my $src = $c->get_source();
is($src->{'my-field-one'}, 'myvalue1', "Access field through badly capitalized field name");
is($src->{'long-field'}, 
'line1
 line 2 line 2 line 2
 line 3 line 3 line 3', "Get multi-line field");
is($src->{'Empty-field'}, "", "Get empty field");

my $pkg = $c->get_pkg_by_idx(1);
is($pkg->{package}, 'mypackage1', 'Name of first package');

$pkg = $c->get_pkg_by_name("mypackage3");
is($pkg->{package}, 'mypackage3', 'Name of third package');
is($pkg->{Depends}, 'hello', 'Name of third package');

$pkg = $c->get_pkg_by_idx(2);
$io = IO::String->new();
tied(%{$pkg})->dump($io);

is(${$io->string_ref()},
'Package: mypackage2
Depends: hello
', "Dump of second binary package of $srcdir/control-1");

