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

use Test::More tests => 64;

use_ok('Dpkg::Arch', qw(debarch_to_debtriplet debarch_to_multiarch
                        debarch_eq debarch_is debarch_is_wildcard
                        debarch_is_illegal
                        debarch_to_cpuattrs
                        debarch_list_parse
                        debtriplet_to_debarch gnutriplet_to_debarch
                        get_host_gnu_type
                        get_valid_arches));

my @tuple_new;
my @tuple_ref;

@tuple_new = debarch_to_debtriplet('unknown');
is_deeply(\@tuple_new, [], 'unknown triplet');

@tuple_ref = qw(gnu linux amd64);
@tuple_new = debarch_to_debtriplet('amd64');
is_deeply(\@tuple_new, \@tuple_ref, 'valid triplet');

@tuple_ref = qw(gnu linux amd64);
@tuple_new = debarch_to_debtriplet('amd64');
is_deeply(\@tuple_new, \@tuple_ref, 'valid triplet');
@tuple_new = debarch_to_debtriplet('linux-amd64');
is_deeply(\@tuple_new, \@tuple_ref, 'valid triplet');

is(debarch_to_multiarch('i386'), 'i386-linux-gnu',
   'normalized i386 multiarch triplet');
is(debarch_to_multiarch('amd64'), 'x86_64-linux-gnu',
   'normalized amd64 multiarch triplet');

ok(!debarch_eq('amd64', 'i386'), 'no match, simple arch');
ok(!debarch_eq('', 'amd64'), 'no match, empty first arch');
ok(!debarch_eq('amd64', ''), 'no match, empty second arch');
ok(!debarch_eq('amd64', 'unknown'), 'no match, with first unknown arch');
ok(!debarch_eq('unknown', 'i386'), 'no match, second unknown arch');
ok(debarch_eq('unknown', 'unknown'), 'match equal unknown arch');
ok(debarch_eq('amd64', 'amd64'), 'match equal known arch');
ok(debarch_eq('amd64', 'linux-amd64'), 'match implicit linux arch');

ok(!debarch_is('unknown', 'linux-any'), 'no match unknown on wildcard cpu');
ok(!debarch_is('unknown', 'any-amd64'), 'no match unknown on wildcard os');
ok(!debarch_is('amd64', 'unknown'), 'no match amd64 on unknown wildcard');
ok(!debarch_is('amd64', 'unknown-any'), 'no match amd64 on unknown wildcard');
ok(!debarch_is('amd64', 'any-unknown'), 'no match amd64 on unknown wildcard');
ok(debarch_is('unknown', 'any'), 'match unknown on global wildcard');
ok(debarch_is('amd64', 'linux-any'), 'match amd64 on wildcard cpu');
ok(debarch_is('amd64', 'any-amd64'), 'match amd64 on wildcard os');
ok(debarch_is('x32', 'any-amd64'), 'match x32 on amd64 wildcard os');
ok(debarch_is('i386', 'any-i386'), 'match i386 on i386 wildcard os');
ok(debarch_is('arm', 'any-arm'), 'match arm on arm wildcard os');
ok(debarch_is('armel', 'any-arm'), 'match armel on arm wildcard os');
ok(debarch_is('armhf', 'any-arm'), 'match armhf on arm wildcard os');

ok(debarch_is('amd64', 'gnu-any-any'), 'match amd64 on abi wildcard');
ok(debarch_is('linux-amd64', 'gnu-any-any'),
   'match linux-amd64 on abi wildcard');
ok(debarch_is('kfreebsd-amd64', 'gnu-any-any'),
   'match kfreebsd-amd64 on abi wildcard');

ok(!debarch_is_wildcard('unknown'), 'unknown is not a wildcard');
ok(!debarch_is_wildcard('all'), 'all is not a wildcard');
ok(!debarch_is_wildcard('amd64'), '<arch> is not a wildcard');
ok(debarch_is_wildcard('any'), '<any> is a global wildcard');
ok(debarch_is_wildcard('any-any'), '<any>-<any> is a wildcard');
ok(debarch_is_wildcard('any-any-any'), '<any>-<any>-<any> is a wildcard');
ok(debarch_is_wildcard('linux-any'), '<os>-any is a wildcard');
ok(debarch_is_wildcard('any-amd64'), 'any-<cpu> is a wildcard');
ok(debarch_is_wildcard('gnu-any-any'), '<abi>-any-any is a wildcard');
ok(debarch_is_wildcard('any-linux-any'), 'any-<os>-any is a wildcard');
ok(debarch_is_wildcard('any-any-amd64'), 'any-any-<cpu> is a wildcard');

ok(!debarch_is_illegal('0'), '');
ok(!debarch_is_illegal('a'), '');
ok(!debarch_is_illegal('amd64'), '');
ok(!debarch_is_illegal('!arm64'), '');
ok(!debarch_is_illegal('kfreebsd-any'), '');
ok(debarch_is_illegal('!amd64!arm'), '');
ok(debarch_is_illegal('arch%name'), '');
ok(debarch_is_illegal('-any'), '');
ok(debarch_is_illegal('!'), '');

my @arch_new;
my @arch_ref;

@arch_ref = qw(amd64 !arm64 linux-i386 !kfreebsd-any);
@arch_new = debarch_list_parse('amd64  !arm64   linux-i386 !kfreebsd-any');
is_deeply(\@arch_new, \@arch_ref, 'parse valid arch list');

eval { @arch_new = debarch_list_parse('!amd64!arm64') };
ok($@, 'parse concatenated arches failed');

is(debarch_to_cpuattrs(undef), undef, 'undef cpu attrs');
is_deeply([ debarch_to_cpuattrs('amd64') ], [ qw(64 little) ], 'amd64 cpu attrs');

is(debtriplet_to_debarch(undef, undef, undef), undef, 'undef debtriplet');
is(debtriplet_to_debarch('gnu', 'linux', 'amd64'), 'amd64', 'known debtriplet');
is(debtriplet_to_debarch('unknown', 'unknown', 'unknown'), undef, 'unknown debtriplet');

is(gnutriplet_to_debarch(undef), undef, 'undef gnutriplet');
is(gnutriplet_to_debarch('unknown-unknown-unknown'), undef, 'unknown gnutriplet');
is(gnutriplet_to_debarch('x86_64-linux-gnu'), 'amd64', 'known gnutriplet');

is(scalar get_valid_arches(), 475, 'expected amount of known architectures');

{
    local $ENV{CC} = 'false';
    is(get_host_gnu_type(), '', 'CC does not support -dumpmachine');

    $ENV{CC} = 'echo CC';
    is(get_host_gnu_type(), 'CC -dumpmachine',
       'CC does not report expected synthetic result for -dumpmachine');
}

1;
