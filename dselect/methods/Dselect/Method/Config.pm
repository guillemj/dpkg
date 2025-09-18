# Copyright © 2009-2010 Raphaël Hertzog <hertzog@debian.org>
# Copyright © 2013-2025 Guillem Jover <guillem@debian.org>
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

Dselect::Method::Config - parse dselect method configuration files

=head1 DESCRIPTION

This class can be used to read and write dselect method options from a
configuration file. It has accessors for the configuration options,
which are stored internally in a hash.

B<Note>: This is a private module, its API can change at any time.

=cut

package Dselect::Method::Config 0.01;

use v5.36;

use Dpkg::Gettext;
use Dpkg::ErrorHandling;

use parent qw(Dpkg::Interface::Storable);

use overload
    '@{}' => sub { return [ $_[0]->get_options() ] },
    fallback => 1;

=head1 METHODS

=over 4

=item $conf = Dselect::Method::Config->new(%opts)

Create a new Dselect::Method::Config object. Some options can be set through
%opts: none currently.

=cut

sub new($this, %opts)
{
    my $class = ref($this) || $this;

    my $self = {
        options => {},
    };
    foreach my $opt (keys %opts) {
        $self->{$opt} = $opts{$opt};
    }
    bless $self, $class;

    return $self;
}

=item @options = @{$conf}

=item @options = $conf->get_options()

Returns the list of option names currently known.

=cut

sub get_options($self)
{
    my @options = sort keys %{$self->{options}};
    return @options;
}

=item $value = $conf->get($name)

Returns the value for the option $name.

=cut

sub get($self, $name)
{
    return $self->{options}->{$name};
}

=item $conf->set($name, $value)

Sets $value for the option $name.

=cut

sub set($self, $name, $value)
{
    $self->{options}->{$name} = $value;

    return;
}

=item $count = $conf->parse($fh)

Parse options from a file handle. When called multiple times, the parsed
options are accumulated.

Return the number of options parsed.

=cut

sub parse($self, $fh, $desc, %opts)
{
    my $count = 0;
    local $_;

    while (<$fh>) {
        chomp;
        # Strip leading spaces.
        s{^\s+}{};
        # Strip trailing spaces.
        s{\s+$}{};
        # Remove spaces around the first =.
        s{\s+=\s+}{=};
        # First spaces becomes = if no =.
        s{\s+}{=} unless m{=};

        # Skip empty lines and comments.
        next if m{^#} or length == 0;

        if (m{^([^=]+)(?:=(.*))?$}) {
            my ($name, $value) = ($1, $2);
            if (defined $value) {
                $value =~ s{^"(.*)"$}{$1} or $value =~ s{^'(.*)'$}{$1};
            }
            $self->{options}{$name} = $value;
            $count++;
        } else {
            warning(g_('invalid syntax for option in %s, line %d'), $desc, $.);
        }
    }

    return $count;
}

=item $count = $conf->load($file)

Read options from a file.

Return the number of options parsed.

=item $conf->filter(%opts)

Filter the list of options, either removing or keeping all those that
return true when $opts{remove}->($option) or $opts{keep}->($option) is called.

=cut

sub filter($self, %opts)
{
    my $remove = $opts{remove} // sub { 0 };
    my $keep = $opts{keep} // sub { 1 };

    foreach my $name (keys %{$self->{options}}) {
        my $option = $name;

        if ($remove->($option) or not $keep->($option)) {
            delete $self->{options}->{$name};
        }
    }

    return;
}

=item $string = $conf->output([$fh])

Write the options in the given filehandle (if defined) and return a string
representation of the content (that would be) written.

=item $string = "$conf"

Return a string representation of the content.

=cut

sub output($self, $fh //= undef, %opts)
{
    my $ret = q{};

    foreach my $name ($self->get_options()) {
        my $value = $self->{options}->{$name} // q{};

        my $opt = "$name=\"$value\"\n";
        print { $fh } $opt if defined $fh;
        $ret .= $opt;
    }

    return $ret;
}

=item $conf->save($file)

Save the options in a file.

=back

=head1 CHANGES

=head2 Version 0.xx

This is a private module.

=cut

1;
