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

use Test::More tests => 32;

use strict;
use warnings;

use Dpkg qw();
use Dpkg::Arch qw(get_host_arch);

use_ok('Dpkg::Substvars');

my $srcdir = $ENV{srcdir} || '.';
my $datadir = $srcdir . '/t/750_Dpkg_Substvars';

my $s = Dpkg::Substvars->new();

$s->load("$datadir/substvars1");

# simple value tests
is($s->get('var1'), 'Some value', 'var1');
is($s->get('var2'), 'Some other value', 'var2');
is($s->get('var3'), 'Yet another value', 'var3');
is($s->get('var4'), undef, 'no var4');

# overriding
$s->set('var1', 'New value');
is($s->get('var1'), 'New value','var1 updated');

# deleting
$s->delete('var3');
is($s->get('var3'), undef, 'var3 deleted');

# default variables
is($s->get('Newline'), "\n", 'newline');
is($s->get('Space'), ' ', 'space');
is($s->get('Tab'), "\t", 'tab');
is($s->get('dpkg:Version'), $Dpkg::PROGVERSION, 'dpkg version 1');

# special variables
is($s->get('Arch'), undef, 'no arch');
$s->set_arch_substvars();
is($s->get('Arch'), get_host_arch(),'arch');

is($s->get($_), undef, 'no ' . $_) for qw/binary:Version source:Version source:Upstream-Version/;
$s->set_version_substvars('1:2.3.4~5-6.7.8~nmu9', '1:2.3.4~5-6.7.8~nmu9+bin0');
is($s->get('binary:Version'), '1:2.3.4~5-6.7.8~nmu9+bin0', 'binary:Version');
is($s->get('source:Version'), '1:2.3.4~5-6.7.8~nmu9', 'source:Version');
is($s->get('source:Upstream-Version'), '1:2.3.4~5', 'source:Upstream-Version');
$s->set_version_substvars('2.3.4~5-6.7.8~nmu9+b1', '1:2.3.4~5-6.7.8~nmu9+b1');
is($s->get('binary:Version'), '1:2.3.4~5-6.7.8~nmu9+b1', 'binary:Version');
is($s->get('source:Version'), '2.3.4~5-6.7.8~nmu9', 'source:Version');
is($s->get('source:Upstream-Version'), '2.3.4~5', 'source:Upstream-Version');
$s->set_version_substvars('1:2.3.4~5-6.7.8~nmu9+b0');
is($s->get('binary:Version'), '1:2.3.4~5-6.7.8~nmu9+b0', 'binary:Version');
is($s->get('source:Version'), '1:2.3.4~5-6.7.8~nmu9', 'source:Version');
is($s->get('source:Upstream-Version'), '1:2.3.4~5', 'source:Upstream-Version');

# Replace stuff
is($s->substvars('This is a string ${var1} with variables ${binary:Version}'),
                 'This is a string New value with variables 1:2.3.4~5-6.7.8~nmu9+b0',
                 'substvars simple');

my $output;
$SIG{__WARN__} = sub { $output .= $_[0] };
is($s->substvars('This is a string with unknown variable ${blubb}'),
                 'This is a string with unknown variable ',
                 'substvars missing');
delete $SIG{__WARN__};
is($output, '750_Dpkg_Substvars.t: warning: unknown substitution variable ${blubb}'."\n"
          , 'missing variables warning');

# Recursive replace
$s->set('rvar', 'recursive ${var1}');
is($s->substvars('This is a string with ${rvar}'),
                 'This is a string with recursive New value',
                 'substvars recursive');

# Strange input
is($s->substvars('Nothing to $ ${substitute  here}, is it ${}?, it ${is'),
                 'Nothing to $ ${substitute  here}, is it ${}?, it ${is',
                 'substvars strange');

# Warnings about unused variables
$output = '';
$SIG{__WARN__} = sub { $output .= $_[0] };
$s->warn_about_unused();
delete $SIG{__WARN__};
is($output, "750_Dpkg_Substvars.t: warning: unused substitution variable \${var2}\n",
          , 'unused variables warnings');

# Disable warnings for a certain variable
$s->mark_as_used('var2');
$output = '';
$SIG{__WARN__} = sub { $output .= $_[0] };
$s->warn_about_unused();
delete $SIG{__WARN__};
is($output, '', 'disabled unused variables warnings');
