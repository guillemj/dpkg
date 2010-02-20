# Copyright © 2007 Raphaël Hertzog <hertzog@debian.org>
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

package Dpkg::Vars;

use strict;
use warnings;

our $VERSION = "0.01";

use Dpkg::ErrorHandling;
use Dpkg::Gettext;

use base qw(Exporter);
our @EXPORT = qw($sourcepackage set_source_package);

our $sourcepackage;

sub check_package_name {
    my $name = shift || '';
    $name =~ m/[^-+.0-9a-z]/o &&
        error(_g("source package name `%s' contains illegal character `%s'"),
              $name, $&);
    $name =~ m/^[0-9a-z]/o ||
        error(_g("source package name `%s' starts with non-alphanum"), $name);
}

sub set_source_package {
    my $v = shift;

    check_package_name($v);
    if (defined($sourcepackage)) {
        $v eq $sourcepackage ||
            error(_g("source package has two conflicting values - %s and %s"),
                  $sourcepackage, $v);
    } else {
        $sourcepackage = $v;
    }
}

1;
