# Copyright 2007 Raphaël Hertzog <hertzog@debian.org>

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

package Dpkg::Cdata;

use strict;
use warnings;

use Dpkg::Gettext;
use Dpkg::ErrorHandling qw(syntaxerr);
use Dpkg::Fields qw(capit);;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(parsecdata);

=head1 NAME

Dpkg::Cdata - parse and manipulate a block of RFC822-like fields

=head1 DESCRIPTION

The Dpkg::Cdata module exports one function 'parsecdata' that reads a
block of data (usually a block following the debian/control format)

=head1 FUNCTIONS

=over 4

=item $obj = Dpkg::Cdata::parsecdata($input, $file, %options)

$input is a filehandle, $file is the name of the file corresponding to
$input. %options can contain two parameters: allow_pgp=>1 allows the parser
to extrac the block of a data in a PGP-signed message (defaults to 0),
and allow_duplicate=>1 ask the parser to not fail when it detects
duplicate fields.

The return value is a reference to a tied hash (Dpkg::Fields::Object) that
can be used to access the various fields.

=cut
sub parsecdata {
    my ($input, $file, %options) = @_;

    $options{allow_pgp} = 0 unless exists $options{allow_pgp};
    $options{allow_duplicate} = 0 unless exists $options{allow_duplicate};

    my $paraborder = 1;
    my $fields = undef;
    my $cf = ''; # Current field
    my $expect_pgp_sig = 0;
    while (<$input>) {
	s/\s*\n$//;
	next if (m/^$/ and $paraborder);
	next if (m/^#/);
	$paraborder = 0;
	if (m/^(\S+?)\s*:\s*(.*)$/) {
	    unless (defined $fields) {
		my %f;
		tie %f, "Dpkg::Fields::Object";
		$fields = \%f;
	    }
	    if (exists $fields->{$1}) {
		unless ($options{allow_duplicate}) {
		    syntaxerr($file, sprintf(_g("duplicate field %s found"), capit($1)));
		}
	    }
	    $fields->{$1} = $2;
	    $cf = $1;
	} elsif (m/^\s+\S/) {
	    length($cf) || syntaxerr($file, _g("continued value line not in field"));
	    $fields->{$cf} .= "\n$_";
	} elsif (m/^-----BEGIN PGP SIGNED MESSAGE/) {
	    $expect_pgp_sig = 1;
	    if ($options{allow_pgp}) {
		# Skip PGP headers
		while (<$input>) {
		    last if m/^$/;
		}
	    } else {
		syntaxerr($file, _g("PGP signature not allowed here"));
	    }
	} elsif (m/^$/) {
	    if ($expect_pgp_sig) {
		# Skip empty lines
		$_ = <$input> while defined($_) && $_ =~ /^\s*$/;
		length($_) ||
                    syntaxerr($file, _g("expected PGP signature, found EOF after blank line"));
		s/\n$//;
		m/^-----BEGIN PGP SIGNATURE/ ||
		    syntaxerr($file,
			sprintf(_g("expected PGP signature, found something else \`%s'"), $_));
		# Skip PGP signature
		while (<$input>) {
		    last if m/^-----END PGP SIGNATURE/;
		}
		length($_) ||
                    syntaxerr($file, _g("unfinished PGP signature"));
	    }
	    last; # Finished parsing one block
	} else {
	    syntaxerr($file, _g("line with unknown format (not field-colon-value)"));
	}
    }
    return $fields;
}

=back

=cut
1;
