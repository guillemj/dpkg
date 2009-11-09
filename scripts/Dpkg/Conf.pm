# Copyright © 2009 Raphaël Hertzog <hertzog@debian.org>
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

package Dpkg::Conf;

use strict;
use warnings;

use Dpkg::Gettext;
use Dpkg::ErrorHandling;

use overload
    '@{}' => sub { $_[0]->{'options'} },
    '""'  => sub { join(" ", @{$_[0]->{'options'}}) },
    fallback => 1;

=head1 NAME

Dpkg::Conf - parse dpkg configuration files

=head1 DESCRIPTION

The Dpkg::Conf object can be used to read options from a configuration
file. It can exports an array that can then be parsed exactly like @ARGV.

=head1 FUNCTIONS

=over 4

=item my $conf = Dpkg::Conf->new()

Create a new Dpkg::Conf object.

=cut

sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;

    my $self = {
	options => [],
    };
    bless $self, $class;

    return $self;
}

=item @$conf

Returns the list of options to be parsed.

=item $conf->load($file)

Read options from a file. Return the number of options parsed.

=item $conf->parse($fh)

Parse options from a file handle. Return the number of options parsed.

=cut

sub load {
    my ($self, $file) = @_;
    open(my $fh, "<", $file) or syserr(_g("cannot read %s"), $file);
    my $ret = $self->parse($fh, $file);
    close($fh);
    return $ret;
}

sub parse {
    my ($self, $fh, $desc) = @_;
    my $count = 0;
    while (<$fh>) {
	chomp;
	s/^\s+//; s/\s+$//;   # Strip leading/trailing spaces
	s/\s+=\s+/=/;         # Remove spaces around the first =
	s/\s+/=/ unless m/=/; # First spaces becomes = if no =
	next if /^#/ or /^$/; # Skip empty lines and comments
	if (/^(\S+)(?:=(.*))?$/) {
	    my ($name, $value) = ($1, $2);
	    $name = "--$name" unless $name =~ /^-/;
	    if (defined $value) {
		$value =~ s/^"(.*)"$/$1/ or $value =~ s/^'(.*)'$/$1/;
		push @{$self->{'options'}}, "$name=$value";
	    } else {
		push @{$self->{'options'}}, $name;
	    }
	    $count++;
	} else {
	    warning(_g("invalid syntax for option in %s, line %d"),
		    $desc, $.);
	}
    }
    return $count;
}

=back

=head1 AUTHOR

Raphaël Hertzog <hertzog@debian.org>.

=cut

1;
