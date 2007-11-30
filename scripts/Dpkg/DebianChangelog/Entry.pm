#
# Parse::DebianChangelog::Entry
#
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

Parse::DebianChangelog::Entry - represents one entry in a Debian changelog

=head1 SYNOPSIS

=head1 DESCRIPTION

=head2 Methods

=head3 init

Creates a new object, no options.

=head3 new

Alias for init.

=head3 is_empty

Checks if the object is actually initialized with data. Due to limitations
in Parse::DebianChangelog this currently simply checks if one of the
fields Source, Version, Maintainer, Date, or Changes is initalized.

=head2 Accessors

The following fields are available via accessor functions (all
fields are string values unless otherwise noted):

=over 4

=item *

Source

=item *

Version

=item *

Distribution

=item *

Urgency

=item *

ExtraFields (all fields except for urgency as hash)

=item *

Header (the whole header in verbatim form)

=item *

Changes (the actual content of the bug report, in verbatim form)

=item *

Trailer (the whole trailer in verbatim form)

=item *

Closes (Array of bug numbers)

=item *

Maintainer (name B<and> email address)

=item *

Date

=item *

Timestamp (Date expressed in seconds since the epoche)

=item *

ERROR (last parse error related to this entry in the format described
at Parse::DebianChangelog::get_parse_errors.

=back

=cut

package Parse::DebianChangelog::Entry;

use strict;
use warnings;

use base qw( Class::Accessor );
use Parse::DebianChangelog::Util qw( :all );

Parse::DebianChangelog::Entry->mk_accessors(qw( Closes Changes Maintainer
						MaintainerEmail Date
						Urgency Distribution
						Source Version ERROR
						ExtraFields Header
						Trailer Timestamp ));

sub new {
    return init(@_);
}

sub init {
    my $classname = shift;
    my $self = {};
    bless( $self, $classname );

    return $self;
}

sub is_empty {
    my ($self) = @_;

    return !($self->{Changes}
	     || $self->{Source}
	     || $self->{Version}
	     || $self->{Maintainer}
	     || $self->{Date});
}

1;
__END__

=head1 SEE ALSO

Parse::DebianChangelog

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
