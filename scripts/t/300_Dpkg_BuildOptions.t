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

use Test::More tests => 6;
use Dpkg::ErrorHandling;

use strict;
use warnings;

use_ok('Dpkg::BuildOptions');

{
    no warnings;
    # Disable warnings related to invalid values fed during
    # the tests
    report_options(quiet_warnings => 1);
}

$ENV{DEB_BUILD_OPTIONS} = 'noopt foonostripbar parallel=3 bazNOCHECK';

my $dbo = Dpkg::BuildOptions::parse();

my %dbo = (
	   noopt => undef,
	   foonostripbar => undef,
	   parallel => 3,
	   );
my %dbo2 = (
	    no => undef,
	    opt => undef,
	    'no-strip' => undef,
	    nocheck => undef,
	    parallel => '',
	   );


is_deeply($dbo, \%dbo, 'parse');

$dbo = Dpkg::BuildOptions::parse('no opt no-strip parallel = 5 nocheck');

is_deeply($dbo, \%dbo2, 'parse (param)');

$dbo->{parallel} = 5;
$dbo->{noopt} = undef;

my $env = Dpkg::BuildOptions::set($dbo, 1);

is($ENV{DEB_BUILD_OPTIONS}, $env, 'set (return value)');
is_deeply(Dpkg::BuildOptions::parse(), $dbo, 'set (env)');

$ENV{DEB_BUILD_OPTIONS} = 'foobar';
$dbo = { noopt => undef };
$env = Dpkg::BuildOptions::set($dbo, 0);
is($env, "foobar noopt", 'set (append)');
