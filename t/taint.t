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
use Test::Dpkg qw(:paths);

test_chdir_srcdir();

my @files = Test::Dpkg::all_perl_files();

plan tests => scalar @files;

my $PERL = $ENV{PERL} // $^X // 'perl';

# Detect taint errors.
sub taint_ok {
    my $file = shift;

    my $eval = qx($PERL -Iscripts -Idselect/methods -cwT \"$file\" 2>&1);
    my $ok = ($eval =~ s{^\Q$file\E syntax OK\n$}{}ms) && length $eval == 0;

    ok($ok, "Tainting check $file");
    if (not $ok) {
        diag($eval);
    }
}

for my $file (@files) {
    taint_ok($file);
}
