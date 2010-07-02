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

package Dpkg;

use strict;
use warnings;

our $VERSION = "1.00";

use base qw(Exporter);
our @EXPORT = qw($version $progname $admindir $dpkglibdir $pkgdatadir);

our ($progname) = $0 =~ m#(?:.*/)?([^/]*)#;

# The following lines are automatically fixed at install time
our $version = "1.14";
our $admindir = "/var/lib/dpkg";
our $dpkglibdir = ".";
our $pkgdatadir = "..";
$pkgdatadir = $ENV{DPKG_DATADIR} if defined $ENV{DPKG_DATADIR};

1;
