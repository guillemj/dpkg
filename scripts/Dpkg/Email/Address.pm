# Copyright © 2025 Guillem Jover <guillem@debian.org>
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

=encoding utf8

=head1 NAME

Dpkg::Email::Address - manage an email address

=head1 DESCRIPTION

It provides a class which is able to manage an email address,
as used in L<deb822(5)> data.

=cut

package Dpkg::Email::Address 0.01;

use v5.36;

use Exporter qw(import);

use Dpkg::Gettext;
use Dpkg::ErrorHandling;

use overload
    '""' => sub { return $_[0]->as_string(); };

my $addr_name_regex = qr{
    # Composed of possibly multiple quoted and not-quoted parts.
    (?:
        # Either non-quoted name, without comma.
        [^<>"\cK,]+
    |
        # Or quoted name, with optional comma.
        " [^<>"\cK]+ "
    )*
}x;

my $addr_email_regex = qr{
    # Local part.
    [^@<>"\s\cK]+
    # Separator.
    @
    # Domain part.
    [^@<>"\s\cK]+
}x;

my $addr_regex = qr{
    \s*
    # Address name.
    (
        $addr_name_regex
    )
    # Separated by at least one space.
    \s+
    # Address email in angle brackets.
    <
        (
            $addr_email_regex
        )
    >
    \s*
}x;

=head1 FUNCTIONS

=over 4

=item $regex = REGEX()

Returns the regex used to parse and validate an email address.

It matches two parts, the name and the email.

=cut

sub REGEX()
{
    return $addr_regex;
}

=back

=head1 METHODS

=over 4

=item $addr = Dpkg::Email::Address->new($string)

Create a new object that can hold an email address.

=cut

sub new($this, $str = undef)
{
    my $class = ref($this) || $this;
    my $self = {};
    bless $self, $class;

    $self->parse($str) if defined $str;

    return $self;
}

=item $name = $addr->name([$name])

Get and optionally set the email address name.

Returns the current or new email name.

=cut

sub name($self, $name = undef)
{
    $self->{name} = $name if defined $name;
    return $self->{name};
}

=item $email = $addr->email([$email])

Get and optionally set the email address email.

Returns the current or new email.

=cut

sub email($self, $email = undef)
{
    $self->{email} = $email if defined $email;
    return $self->{email};
}

=item $bool = $addr->parse($string)

Parses $string into the current object replacing the current address.

Will die on parse errors.

=cut

sub parse($self, $str)
{
    if ($str =~ m{^$addr_regex$}) {
        $self->{name} = $1;
        $self->{email} = $2;

        if ($self->{email} !~ m{@.*\.}) {
            warning(g_("email address '%s' with single label domain"), $str);
        }

        return;
    }

    error(g_("invalid email address '%s'"), $str);
}

=item $string = $addr->as_string()

Returns the email address formatted as a string.

=cut

sub as_string($self)
{
    return "$self->{name} <$self->{email}>";
}

=item $hashref = $addr->as_struct()

Returns the email address in a hashref with name and email keys.

=cut

sub as_struct($self)
{
    return {
        name => $self->{name},
        email => $self->{email},
    };
}

=back

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
