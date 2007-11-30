#
# Parse::DebianChangelog::Util
#
# Copyright 1996 Ian Jackson
# Copyright 2005 Frank Lichtenheld <frank@lichtenheld.de>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#

=head1 NAME

Parse::DebianChangelog::Util - utility functions for parsing Debian changelogs

=head1 DESCRIPTION

This is currently only used internally by Parse::DebianChangelog.
There may be still API changes until this module is finalized.

=head2 Functions

=cut

package Parse::DebianChangelog::Util;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
		 find_closes
		 data2rfc822
		 data2rfc822_mult
		 get_dpkg_changes
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
);

=pod

=head3 find_closes

Takes one string as argument and finds "Closes: #123456, #654321" statements
as supported by the Debian Archive software in it. Returns all closed bug
numbers in an array reference.

=cut

sub find_closes {
    my $changes = shift;
    my @closes = ();

    while ($changes && ($changes =~ /closes:\s*(?:bug)?\#?\s?\d+(?:,\s*(?:bug)?\#?\s?\d+)*/ig)) {
	push(@closes, $& =~ /\#?\s?(\d+)/g);
    }

    @closes = sort { $a <=> $b } @closes;
    return \@closes;
}

=pod

=head3 data2rfc822

Takes two hash references as arguments. The first should contain the
data to output in RFC822 format. The second can contain a sorting order
for the fields. The higher the numerical value of the hash value, the
earlier the field is printed if it exists.

Return the data in RFC822 format as string.

=cut

sub data2rfc822 {
    my ($data, $fieldimps) = @_;
    my $rfc822_str = '';

# based on /usr/lib/dpkg/controllib.pl
    for my $f (sort { $fieldimps->{$b} <=> $fieldimps->{$a} } keys %$data) {
	my $v= $data->{$f} or next;
	$v =~ m/\S/o || next; # delete whitespace-only fields
	$v =~ m/\n\S/o
	    && warn(__g("field %s has newline then non whitespace >%s<",
			$f, $v ));
	$v =~ m/\n[ \t]*\n/o && warn(__g("field %s has blank lines >%s<",
					 $f, $v ));
	$v =~ m/\n$/o && warn(__g("field %s has trailing newline >%s<",
				  $f, $v ));
	$v =~ s/\$\{\}/\$/go;
	$rfc822_str .= "$f: $v\n";
    }

    return $rfc822_str;
}

=pod

=head3 data2rfc822_mult

The first argument should be an array ref to an array of hash references.
The second argument is a hash reference and has the same meaning as
the second argument of L<data2rfc822>.

Calls L<data2rfc822> for each element of the array given as first
argument and returns the concatenated results.

=cut

sub data2rfc822_mult {
    my ($data, $fieldimps) = @_;
    my @rfc822 = ();

    foreach my $entry (@$data) {
	push @rfc822, data2rfc822($entry,$fieldimps);
    }

    return join "\n", @rfc822;
}

=pod

=head3 get_dpkg_changes

Takes a Parse::DebianChangelog::Entry object as first argument.

Returns a string that is suitable for using it in a C<Changes> field
in the output format of C<dpkg-parsechangelog>.

=cut

sub get_dpkg_changes {
    my $changes = "\n ".($_[0]->Header||'')."\n .\n".($_[0]->Changes||'');
    chomp $changes;
    $changes =~ s/^ $/ ./mgo;
    return $changes;
}

1;
__END__

=head1 SEE ALSO

Parse::DebianChangelog, Parse::DebianChangelog::Entry

=head1 AUTHOR

Frank Lichtenheld, E<lt>frank@lichtenheld.deE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2005 by Frank Lichtenheld

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

=cut
