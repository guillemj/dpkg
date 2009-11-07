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

package Dpkg::Compression;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw(@comp_supported %comp_supported %comp_ext $comp_regex
		 %comp_prog %comp_decomp_prog
		 get_compression_from_filename);

our @comp_supported = qw(gzip bzip2 lzma xz);
our %comp_supported = map { $_ => 1 } @comp_supported;
our %comp_ext = (gzip => 'gz', bzip2 => 'bz2', lzma => 'lzma', xz => 'xz');
our $comp_regex = '(?:gz|bz2|lzma|xz)';
our %comp_prog = (gzip => 'gzip', bzip2 => 'bzip2', lzma => 'lzma',
		  xz => 'xz');
our %comp_decomp_prog = (gzip => 'gunzip', bzip2 => 'bunzip2', lzma => 'unlzma',
			 xz => 'unxz');

sub get_compression_from_filename {
    my $filename = shift;
    foreach my $comp (@comp_supported) {
        if ($filename =~ /^(.*)\.\Q$comp_ext{$comp}\E$/) {
	    return $comp;
        }
    }
    return undef;
}

1;
