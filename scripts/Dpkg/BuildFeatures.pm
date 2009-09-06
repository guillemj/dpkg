# Copyright © 2007 Frank Lichtenheld <djpig@debian.org>
# Copyright © 2010-2011 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2010-2011 Bill Allombert <ballombe@debian.org>
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

package Dpkg::BuildFeatures;

use strict;
use warnings;

our $VERSION = "0.01";

use Dpkg::Control::Info;

=encoding utf8

=head1 NAME

Dpkg::BuildFeatures - parse the Build-Features control field

=head1 DESCRIPTION

The Dpkg::BuildFeatures object can be used to query the options
stored in the Build-Features control field.

=head1 FUNCTIONS

=over 4

=item my $bf = Dpkg::BuildFeatures->new($controlfile)

Create a new Dpkg::BuildFeatures object. It will be initialized based
on the value of the Build-Features control field. If $controlfile is omitted, it
loads debian/control.

=cut

sub new {
    my ($this, $controlfile) = @_;
    my $class = ref($this) || $this;
    my $control = Dpkg::Control::Info->new($controlfile);
    my $src_fields = $control->get_source();
    my %buildfeats;
    if (defined($src_fields->{'Build-Features'})) {
        my @buildfeats = split(/\s*,\s*/m, $src_fields->{'Build-Features'});
        %buildfeats = map { $_ => 1 } @buildfeats;
    }
    my $self = { options => \%buildfeats };
    bless $self, $class;
    return $self;
}

=item $bf->has($option)

Returns a boolean indicating whether the option is stored in the object.

=cut

sub has {
    my ($self, $key) = @_;
    return exists $self->{'options'}{$key};
}

=back

=head1 AUTHOR

Bill Allombert <ballombe@debian.org>

=cut

1;
