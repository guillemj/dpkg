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

use Test::More tests => 24;
use Dpkg::ErrorHandling;

use strict;
use warnings;

use_ok('Dpkg::BuildOptions');

{
    no warnings; ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    # Disable warnings related to invalid values fed during
    # the tests
    report_options(quiet_warnings => 1);
}

$ENV{DEB_BUILD_OPTIONS} = 'noopt foonostripbar parallel=3 bazNOCHECK';

my $dbo = Dpkg::BuildOptions->new();
ok($dbo->has("noopt"), "has noopt");
is($dbo->get("noopt"), undef, "noopt value");
ok($dbo->has("foonostripbar"), "has foonostripbar");
is($dbo->get("foonostripbar"), undef, "foonostripbar value");
ok($dbo->has("parallel"), "has parallel");
is($dbo->get("parallel"), 3, "parallel value");
ok(!$dbo->has("bazNOCHECK"), "not has bazNOCHECK");

$dbo->reset();
$dbo->merge('no opt no-strip parallel = 5 nocheck', 'test');
ok($dbo->has('no'), "has no");
is($dbo->get('no'), undef, "no value");
ok($dbo->has('opt'), "has opt");
is($dbo->get('opt'), undef, "opt value");
ok($dbo->has('no-strip'), "has no-strip");
is($dbo->get('no-strip'), undef, "no-strip value");
ok($dbo->has('parallel'), "has parallel");
is($dbo->get('parallel'), '', "parallel value");
ok($dbo->has('nocheck'), "has nocheck");
is($dbo->get('nocheck'), undef, "nocheck value");

$dbo->reset();
$dbo->set('parallel', 5);
$dbo->set('noopt', undef);

my $env = $dbo->export();
is($env, "noopt parallel=5", "value of export");
is($ENV{DEB_BUILD_OPTIONS}, $env, 'env match return value of export');
$env = $dbo->export("OTHER_VARIABLE");
is($ENV{OTHER_VARIABLE}, $env, 'export to other variable');

$ENV{DEB_BUILD_OPTIONS} = 'foobar';
$dbo = Dpkg::BuildOptions->new();
$dbo->set("noopt", 1);
is($dbo->output(), "foobar noopt", "output");

$dbo = Dpkg::BuildOptions->new(envvar => "OTHER_VARIABLE");
is($dbo->get("parallel"), 5, "import from other variable, check parallel");
ok($dbo->has("noopt"), "import from other variable, check noopt");
