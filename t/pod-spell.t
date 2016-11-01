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
use Test::Dpkg qw(:needs);

test_needs_author();
test_needs_module('Test::Spelling');
test_needs_command('aspell');

if (qx(aspell dicts) !~ m/en_US/) {
    plan skip_all => 'aspell en_US dictionary required for spell checking POD';
}

test_needs_srcdir_switch();

my @files = Test::Dpkg::all_perl_files();

plan tests => scalar @files;

set_spell_cmd('aspell list --encoding UTF-8 -l en_US -p /dev/null');
add_stopwords(<DATA>);

for my $file (@files) {
    pod_file_spelling_ok($file);
}

__DATA__
CVS
DSC
Dpkg
IPC
ORed
OpenPGP
XDG
archqual
buildinfo
bzip2
canonicalized
checksum
checksums
cmdline
debian
decompressor
dep
deps
dpkg
dpkg-buildflags
dpkg-checkbuilddeps
dpkg-dev
dpkg-genbuildinfo
dpkg-gencontrol
dpkg-parsechangelog
dsc
dup'ed
env
envvar
fieldnames
ge
gettext
hurd
keyrings
le
lzma
multiarch
nocheck
qa
reportfile
rfc822
sig
substvar
substvars
unparsed
update-buildflags
xz
