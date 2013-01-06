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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;

use Test::More tests => 20;
use Dpkg::Arch qw(get_host_arch);

use_ok('Dpkg::Deps');

my $field_multiline = ' , , libgtk2.0-common (= 2.10.13-1)  , libatk1.0-0 (>=
1.13.2), libc6 (>= 2.5-5), libcairo2 (>= 1.4.0), libcupsys2 (>= 1.2.7),
libfontconfig1 (>= 2.4.0), libglib2.0-0  (  >= 2.12.9), libgnutls13 (>=
1.6.3-0), libjpeg62, python (<< 2.5) , , ';
my $field_multiline_sorted = 'libatk1.0-0 (>= 1.13.2), libc6 (>= 2.5-5), libcairo2 (>= 1.4.0), libcupsys2 (>= 1.2.7), libfontconfig1 (>= 2.4.0), libglib2.0-0 (>= 2.12.9), libgnutls13 (>= 1.6.3-0), libgtk2.0-common (= 2.10.13-1), libjpeg62, python (<< 2.5)';

my $dep_multiline = deps_parse($field_multiline);
$dep_multiline->sort();
is($dep_multiline->output(), $field_multiline_sorted, 'Parse, sort and output');

my $dep_subset = deps_parse('libatk1.0-0 (>> 1.10), libc6, libcairo2');
is($dep_multiline->implies($dep_subset), 1, 'Dep implies subset of itself');
is($dep_subset->implies($dep_multiline), undef, "Subset doesn't imply superset");
my $dep_opposite = deps_parse('python (>= 2.5)');
is($dep_opposite->implies($dep_multiline), 0, 'Opposite condition implies NOT the depends');

my $dep_or1 = deps_parse('a|b (>=1.0)|c (>= 2.0)');
my $dep_or2 = deps_parse('x|y|a|b|c (<= 0.5)|c (>=1.5)|d|e');
is($dep_or1->implies($dep_or2), 1, 'Implication between OR 1/2');
is($dep_or2->implies($dep_or1), undef, 'Implication between OR 2/2');

my $dep_ma_any = deps_parse('libcairo2:any');
my $dep_ma_native = deps_parse('libcairo2');
#my $dep_ma_native2 = deps_parse('libcairo2:native');
is($dep_ma_native->implies($dep_ma_any), 1, 'foo -> foo:any');
#is($dep_ma_native2->implies($dep_ma_any), 1, 'foo:native -> foo:any');
is($dep_ma_any->implies($dep_ma_native), undef, 'foo:any !-> foo');
#is($dep_ma_any->implies($dep_ma_native2), undef, 'foo:any !-> foo:native');

my $field_arch = 'libc6 (>= 2.5) [!alpha !hurd-i386], libc6.1 [alpha], libc0.1 [hurd-i386]';
my $dep_i386 = deps_parse($field_arch, reduce_arch => 1, host_arch => 'i386');
my $dep_alpha = deps_parse($field_arch, reduce_arch => 1, host_arch => 'alpha');
my $dep_hurd = deps_parse($field_arch, reduce_arch => 1, host_arch => 'hurd-i386');
is($dep_i386->output(), 'libc6 (>= 2.5)', 'Arch reduce 1/3');
is($dep_alpha->output(), 'libc6.1', 'Arch reduce 2/3');
is($dep_hurd->output(), 'libc0.1', 'Arch reduce 3/3');


my $facts = Dpkg::Deps::KnownFacts->new();
$facts->add_installed_package('mypackage', '1.3.4-1', get_host_arch(), 'no');
$facts->add_installed_package('mypackage2', '1.3.4-1', 'somearch', 'no');
$facts->add_installed_package('pkg-ma-foreign', '1.3.4-1', 'somearch', 'foreign');
$facts->add_installed_package('pkg-ma-foreign2', '1.3.4-1', get_host_arch(), 'foreign');
$facts->add_installed_package('pkg-ma-allowed', '1.3.4-1', 'somearch', 'allowed');
$facts->add_installed_package('pkg-ma-allowed2', '1.3.4-1', 'somearch', 'allowed');
$facts->add_installed_package('pkg-ma-allowed3', '1.3.4-1', get_host_arch(), 'allowed');
$facts->add_provided_package('myvirtual', undef, undef, 'mypackage');

my $field_duplicate = 'libc6 (>= 2.3), libc6 (>= 2.6-1), mypackage (>=
1.3), myvirtual | something, python (>= 2.5), mypackage2, pkg-ma-foreign,
pkg-ma-foreign2, pkg-ma-allowed:any, pkg-ma-allowed2, pkg-ma-allowed3';
my $dep_dup = deps_parse($field_duplicate);
$dep_dup->simplify_deps($facts, $dep_opposite);
is($dep_dup->output(), 'libc6 (>= 2.6-1), mypackage2, pkg-ma-allowed2', 'Simplify deps');

my $field_dup_union = 'libc6 (>> 2.3), libc6 (>= 2.6-1), fake (<< 2.0),
fake(>> 3.0), fake (= 2.5), python (<< 2.5), python (= 2.4)';
my $dep_dup_union = deps_parse($field_dup_union, union => 1);
$dep_dup_union->simplify_deps($facts);
is($dep_dup_union->output(), 'libc6 (>> 2.3), fake (<< 2.0), fake (>> 3.0), fake (= 2.5), python (<< 2.5)', 'Simplify union deps');

$dep_dup_union = deps_parse('sipsak (<= 0.9.6-2.1), sipsak (<= 0.9.6-2.2)', union => 1);
$dep_dup_union->simplify_deps($facts);
is($dep_dup_union->output(), 'sipsak (<= 0.9.6-2.2)', 'Simplify union deps 2');

my $dep_red = deps_parse('abc | xyz, two, abc');
$dep_red->simplify_deps($facts, $dep_opposite);
is($dep_red->output(), 'abc, two', 'Simplification respect order');
is("$dep_red", $dep_red->output(), 'Stringification == output()');

my $dep_empty1 = deps_parse('');
is($dep_empty1->output(), '', 'Empty dependency');

my $dep_empty2 = deps_parse(' , , ', union => 1);
is($dep_empty2->output(), '', "' , , ' is also an empty dependency");

$SIG{__WARN__} = sub {};
my $dep_bad_multiline = deps_parse("a, foo\nbar, c");
ok(!defined($dep_bad_multiline), 'invalid dependency split over multiple line');
delete $SIG{__WARN__};
