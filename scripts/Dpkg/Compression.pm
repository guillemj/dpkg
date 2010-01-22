# Copyright © 2010 Raphaël Hertzog <hertzog@debian.org>
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

package Dpkg::Compression;

use strict;
use warnings;

use base qw(Exporter);
our @EXPORT = qw($compression_re_file_ext compression_get_list
		 compression_is_supported compression_get_property
		 compression_guess_from_filename);

=head1 NAME

Dpkg::Compression - simple database of available compression methods

=head1 DESCRIPTION

This modules provides a few public funcions and a public regex to
interact with the set of supported compression methods.

=head1 EXPORTED VARIABLES

=over 4

=cut

my $COMP = {
    "gzip" => {
	"file_ext" => "gz",
	"comp_prog" => "gzip",
	"decomp_prog" => "gunzip",
    },
    "bzip2" => {
	"file_ext" => "bz2",
	"comp_prog" => "bzip2",
	"decomp_prog" => "bunzip2",
    },
    "lzma" => {
	"file_ext" => "lzma",
	"comp_prog" => "lzma",
	"decomp_prog" => "unlzma",
    },
    "xz" => {
	"file_ext" => "xz",
	"comp_prog" => "xz",
	"decomp_prog" => "unxz",
    },
};

=item $compression_re_file_ext

A regex that matches a file extension of a file compressed with one of the
supported compression methods.

=back

=cut

my $regex = join "|", map { $_->{"file_ext"} } values %$COMP;
our $compression_re_file_ext = qr/(?:$regex)/;

=head1 EXPORTED FUNCTIONS

=over 4

=item my @list = compression_get_list()

Returns a list of supported compression methods (sorted alphabetically).

=cut

sub compression_get_list {
    return sort keys %$COMP;
}

=item compression_is_supported($comp)

Returns a boolean indicating whether the give compression method is
known and supported.

=cut

sub compression_is_supported {
    return exists $COMP->{$_[0]};
}

=item compression_get_property($comp, $property)

Returns the requested property of the compression method. Returns undef if
either the property or the compression method doesn't exist. Valid
properties currently include "file_ext" for the file extension,
"comp_prog" for the name of the compression program and "decomp_prog" for
the name of the decompression program.

=cut

sub compression_get_property {
    my ($comp, $property) = @_;
    return undef unless compression_is_supported($comp);
    return $COMP->{$comp}{$property} if exists $COMP->{$comp}{$property};
    return undef;
}

=item compression_guess_from_filename($filename)

Returns the compression method that is likely used on the indicated
filename based on its file extension.

=cut

sub compression_guess_from_filename {
    my $filename = shift;
    foreach my $comp (compression_get_list()) {
	my $ext = compression_get_property($comp, "file_ext");
        if ($filename =~ /^(.*)\.\Q$ext\E$/) {
	    return $comp;
        }
    }
    return undef;
}

=back

=head1 AUTHOR

Raphaël Hertzog <hertzog@debian.org>.

=cut

1;
