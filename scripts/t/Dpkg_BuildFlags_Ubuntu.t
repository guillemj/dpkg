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

use Test::More tests => 16;

BEGIN {
    use_ok('Dpkg::BuildFlags');
}

sub test_optflag
{
    my ($bf, $optflag) = @_;

    foreach my $flag (qw(CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS GCJFLAGS
                         FFLAGS FCFLAGS)) {
        my $value = $bf->get($flag);
        ok($value =~ m/$optflag/, "$flag contains $optflag: $value");
    }
}

my $bf;

# Force loading the Dpkg::Vendor::Ubuntu module.
$ENV{DEB_VENDOR} = 'Ubuntu';

# Test the optimization flag inherited from the Dpkg::Vendor::Debian module.
$ENV{DEB_HOST_ARCH} = 'amd64';
$bf = Dpkg::BuildFlags->new();

test_optflag($bf, '-O2');

# Test the overlaid Ubuntu-specific linker flag.
ok($bf->get('LDFLAGS') =~ m/-Wl,-Bsymbolic-functions/,
   'LDFLAGS contains -Bsymbolic-functions');

# Test the optimization flag override only for ppc64el.
$ENV{DEB_HOST_ARCH} = 'ppc64el';
$bf = Dpkg::BuildFlags->new();

test_optflag($bf, '-O3');

1;
