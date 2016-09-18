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

use File::Find;

use Test::More;
use Test::Dpkg qw(:needs);

test_needs_author();
test_needs_module('Test::Pod::Coverage');
test_needs_srcdir_switch();

sub all_pod_modules
{
    my @modules;
    my $scan_perl_modules = sub {
        my $module = $File::Find::name;

        # Only chack modules, scripts are documented in man pages.
        return unless $module =~ s/\.pm$//;

        # As a first step just check public modules (version > 0.xx).
        return unless system('grep', '-q', '^our \$VERSION = \'[^0]\.',
                                     $File::Find::name) == 0;

        $module =~ s{^\Q$File::Find::topdir\E/}{};

        push @modules, $module =~ s{/}{::}gr;
    };

    my %options = (
        wanted => $scan_perl_modules,
        no_chdir => 1,
    );
    find(\%options, Test::Dpkg::test_get_perl_dirs());

    return @modules;
}

my @modules = all_pod_modules();

plan tests => scalar @modules;

for my $module (@modules) {
    pod_coverage_ok($module);
}
