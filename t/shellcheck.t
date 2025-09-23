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
test_needs_command('shellcheck');

test_chdir_srcdir();

my @files_todo = qw(
    dselect/methods/file/install.sh
    dselect/methods/file/setup.sh
    dselect/methods/file/update.sh
    dselect/methods/media/install.sh
    dselect/methods/media/setup.sh
    dselect/methods/media/update.sh
);
my @files = all_shell_files(@files_todo);

my @shellcheck_opts = (
    '--external-sources', # Allow checking external source files.
    '--exclude=SC1090', # Allow non-constant source.
    '--exclude=SC2039', # Allow local keyword.
    '--exclude=SC2166', # Allow -a and -o.
    '--exclude=SC2034', # Allow unused variables for colors.
    '--exclude=SC3043', # Allow local keyword.
);

plan tests => scalar @files + scalar @files_todo;

sub shell_syntax_ok
{
    my $file = shift;

    my $tags = qx(shellcheck @shellcheck_opts $file 2>&1);

    # Fixup the output:
    chomp $tags;

    my $ok = length $tags == 0;

    ok($ok, 'shellcheck');
    if (not $ok) {
        diag($tags);
    }
}

foreach my $file (@files) {
    shell_syntax_ok($file);
}

TODO: {
    local $TODO = 'shell scripts not yet fixed';

    foreach my $file (@files_todo) {
        shell_syntax_ok($file);
    }
}
