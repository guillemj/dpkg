# Copyright © 2015 Guillem Jover <guillem@debian.org>
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

package Test::Dpkg;

use strict;
use warnings;

our $VERSION = '0.00';
our @EXPORT_OK = qw(all_perl_files);

use Exporter qw(import);
use File::Find;

sub all_perl_files
{
    my @files;
    my $scan_perl_files = sub {
        push @files, $File::Find::name if m/\.(pl|pm|t)$/;
    };

    find($scan_perl_files, qw(t src/t lib utils/t scripts dselect));

    return @files;
}

1;
