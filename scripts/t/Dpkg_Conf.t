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

use Test::More tests => 14;

BEGIN {
    use_ok('Dpkg::Conf');
}

my $srcdir = $ENV{srcdir} // '.';
my $datadir = $srcdir . '/t/Dpkg_Conf';

my ($conf, $count, @opts);

my @expected_long_opts = (
'--l=v',
'--option-dash=value-dash',
'--option-double-quotes=value double quotes',
'--option-equal=value-equal=subvalue-equal',
'--option-indent=value-indent',
'--option-name=value-name',
'--option-noequal=value-noequal',
'--option-simple',
'--option-single-quotes=value single quotes',
'--option-space=value words space',
);
my @expected_short_opts = qw(
-o=vd
-s
);

$conf = Dpkg::Conf->new();
local $SIG{__WARN__} = sub { };
$count = $conf->load("$datadir/config-mixed");
delete $SIG{__WARN__};
is($count, 10, 'Load a config file, only long options');

@opts = $conf->get_options();
is_deeply(\@opts, \@expected_long_opts, 'Parse long options');

$conf = Dpkg::Conf->new(allow_short => 1);
$count = $conf->load("$datadir/config-mixed");
is($count, 12, 'Load a config file, mixed options');

@opts = $conf->get_options();
my @expected_mixed_opts = ( @expected_short_opts, @expected_long_opts );
is_deeply(\@opts, \@expected_mixed_opts, 'Parse mixed options');

my $expected_mixed_output = <<'MIXED';
-o = "vd"
-s
l = "v"
option-dash = "value-dash"
option-double-quotes = "value double quotes"
option-equal = "value-equal=subvalue-equal"
option-indent = "value-indent"
option-name = "value-name"
option-noequal = "value-noequal"
option-simple
option-single-quotes = "value single quotes"
option-space = "value words space"
MIXED

is($conf->output, $expected_mixed_output, 'Output mixed options');

is($conf->get('-o'), 'vd', 'Get option -o');
is($conf->get('option-dash'), 'value-dash', 'Get option-dash');
is($conf->get('option-space'), 'value words space', 'Get option-space');

is($conf->get('manual-option'), undef, 'Get non-existent option');
$conf->set('manual-option', 'manual value');
is($conf->get('manual-option'), 'manual value', 'Get manual option');

my $expected_filter;

$expected_filter = <<'FILTER';
-o = "vd"
-s
l = "v"
FILTER

$conf = Dpkg::Conf->new(allow_short => 1);
$conf->load("$datadir/config-mixed");
$conf->filter(format_argv => 1, remove => sub { $_[0] =~ m/^--option/ });
is($conf->output, $expected_filter, 'Filter remove');

$expected_filter = <<'FILTER';
option-double-quotes = "value double quotes"
option-single-quotes = "value single quotes"
FILTER

$conf = Dpkg::Conf->new(allow_short => 1);
$conf->load("$datadir/config-mixed");
$conf->filter(keep => sub { $_[0] =~ m/^option-[a-z]+-quotes/ });
is($conf->output, $expected_filter, 'Filter keep');

$expected_filter = <<'FILTER';
l = "v"
FILTER

$conf = Dpkg::Conf->new(allow_short => 1);
$conf->load("$datadir/config-mixed");
$conf->filter(format_argv => 1,
              remove => sub { $_[0] =~ m/^--option/ },
              keep => sub { $_[0] =~ m/^--/ });
is($conf->output, $expected_filter, 'Filter keep and remove');

1;
