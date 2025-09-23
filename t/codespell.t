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

use v5.36;

use Test::More;
use Test::Dpkg qw(:needs :paths);

test_needs_author();
test_needs_command('codespell');
plan tests => 1;

test_chdir_srcdir();

my @codespell_skip = qw(
    .git
    *.po
    *.pot
    *.gmo
    *.add
    *.cache
    *.policy
    *~
    .libs
    .deps
    ChangeLog
    Makefile.in
    Makefile
    configure
    config.*
    libtool
    libtool.m4
    aclocal.m4
    autom4te.cache
    _build
    build-aux
    build-tree
    tmp
);
my $codespell_skip = join ',', @codespell_skip;

my @codespell_opts = (
    '--ignore-words=t/codespell/stopwords',
    "--skip=$codespell_skip",
);
my $tags = qx(codespell @codespell_opts 2>&1);

# Fixup the output:
$tags =~ s/^WARNING: Binary file:.*\n//mg;
$tags =~ s{^\./build-aux/.*\n}{}mg;
$tags =~ s{^\./man/[a-zA-Z_]+/.*\n}{}mg;
# XXX: Ignore python-3.8 runtime warnings:
$tags =~ s{^.*: RuntimeWarning: line buffering .*\n}{}mg;
$tags =~ s{^\s*file = builtins.open.*\n}{}mg;
chomp $tags;

my $ok = length $tags == 0;

ok($ok, 'codespell');
if (not $ok) {
    diag($tags);
}
